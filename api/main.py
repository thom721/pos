
import asyncio
import logging
from fastapi import FastAPI, Depends, HTTPException, Request
from sqlalchemy import text

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
_log = logging.getLogger("pos.migration")
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.gzip import GZipMiddleware
from api.database import engine, Base
from api.routes import returns, sales, purchases, user, category, customer, product, login, supplier, auth, stock, purchases_receive, payments, debts, config
from api.routes import proformas, invoices, inventory
from api.routes import employees, payroll
from api.routes import setup as setup_router
from api.routes import roles as roles_router
from api.routes import public as public_router
from api.routes import sync as sync_router
from api.routes import webhooks as webhooks_router
from api.routes import billing as billing_router
from api.routes import admin as admin_router
from api.routes import cashier_sessions as cashier_sessions_router
from api.routes import audit as audit_router
from api.routes import warehouse as warehouse_router
from api.routes import reports as reports_router
from api.routes import ws as ws_router
from api.routes import restaurant as restaurant_router
from api.ws_manager import manager as _ws_manager
from api.core.security import verify_token as _verify_token
# Import models so create_all picks them up
from api.models import (  # noqa: F401
    Tenant, PosRegister, CashierSession, OfflineSyncQueue,
    BillingPayment, Proforma, Invoice, InventoryRecord, Role,
    PlatformConfig, SyncState, AuditLog,
)
from api.models.RestaurantTable import RestaurantTable as _RestaurantTable  # noqa: F401
from api.models.RestaurantOrder import RestaurantOrder as _RestaurantOrder, RestaurantOrderItem as _RestaurantOrderItem  # noqa: F401
from api.models.BillingExtra import BillingExtra as _BillingExtra  # noqa: F401 — ensures table creation
from api.models.Ingredient import Ingredient as _Ingredient  # noqa: F401 — ensures table creation
from api.models.ModifierGroup import ModifierGroup as _ModifierGroup, ModifierOption as _ModifierOption  # noqa: F401
from api.models.MenuItem import MenuItem as _MenuItem  # noqa: F401
from api.models.RoomAttribute import RoomAttribute as _RoomAttribute  # noqa: F401 — ensures table creation
from fastapi.staticfiles import StaticFiles
from fastapi.encoders import jsonable_encoder

app = FastAPI()

# ── CORS ──────────────────────────────────────────────────────────────────────
# Configurable via pos_server.ini [server] cors_origins ou CORS_ORIGINS env.
# "*" = tout autoriser (dev / local).
# Production : "https://app.posconnect.ht,https://posconnect.ht"
from api.core.config import settings as _settings_cors

_raw_origins = _settings_cors.CORS_ORIGINS or "*"
_origins: list[str] | str = (
    [o.strip() for o in _raw_origins.split(",") if o.strip()]
    if _raw_origins != "*"
    else ["*"]
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=_origins != ["*"],  # credentials only when origins are explicit
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1024)

# ── Dirty-flag middleware ─────────────────────────────────────────────────────
# Tout POST/PUT/PATCH/DELETE réussi (hors routes de sync elles-mêmes) réveille
# le loop de sync pour une synchronisation quasi-immédiate.
_NO_SIGNAL_PREFIXES = ("/api/sync/push", "/api/sync/pull")

@app.middleware("http")
async def _write_sync_trigger(request: Request, call_next):
    response = await call_next(request)
    if (
        request.method in ("POST", "PUT", "PATCH", "DELETE")
        and response.status_code < 400
        and not any(request.url.path.startswith(p) for p in _NO_SIGNAL_PREFIXES)
    ):
        signal_pending_sync()
        # Push real-time notification to connected WebSocket clients of the same tenant
        auth_header = request.headers.get("authorization", "")
        token = auth_header.removeprefix("Bearer ").strip()
        if token:
            payload = _verify_token(token)
            if payload:
                tid = payload.get("tenant_id")
                if tid and _ws_manager.connection_count(tid) > 0:
                    asyncio.create_task(_ws_manager.notify(tid))
    return response

app.mount("/static", StaticFiles(directory="api/static"), name="static")

app.include_router(user.router, prefix="/api")
app.include_router(login.router)
app.include_router(auth.router)
app.include_router(category.router)
app.include_router(supplier.router, prefix="/api")
app.include_router(product.router)
app.include_router(purchases.router)
app.include_router(purchases_receive.router)
app.include_router(customer.router, prefix="/api")
app.include_router(sales.router)
app.include_router(stock.router)
app.include_router(returns.router, prefix="/api/returns", tags=["Returns"])
app.include_router(restaurant_router.router, prefix="/api/restaurant", tags=["Restaurant"])
app.include_router(payments.router)
app.include_router(debts.router)
app.include_router(config.router)
app.include_router(proformas.router)
app.include_router(invoices.router)
app.include_router(inventory.router)
app.include_router(employees.router)
app.include_router(payroll.router)
app.include_router(setup_router.router, prefix="/api")
app.include_router(roles_router.router)
app.include_router(public_router.router)
app.include_router(sync_router.router)
app.include_router(webhooks_router.router)
app.include_router(billing_router.router)
app.include_router(cashier_sessions_router.router)
app.include_router(audit_router.router)
app.include_router(admin_router.router)
app.include_router(reports_router.router)
app.include_router(warehouse_router.router)
app.include_router(ws_router.router)

# ── Built-in role definitions ─────────────────────────────────────────────────
_BUILTIN_ROLES = [
    {"name": "admin",         "label": "Administrateur", "color": "#7C3AED", "permissions": ["all"]},
    {"name": "manager",       "label": "Gérant",          "color": "#0284C7", "permissions": None},
    {"name": "cashier",       "label": "Caissier",         "color": "#059669", "permissions": None},
    {"name": "stock_manager", "label": "Resp. Stock",      "color": "#D97706", "permissions": None},
    {"name": "waiter",        "label": "Serveur",          "color": "#EA580C", "permissions": None},
]


def _run_alembic_migrations() -> None:
    """
    Applique les migrations Alembic en attente, sérialisées par un verrou MySQL
    advisory pour éviter les conflits entre workers Gunicorn qui démarrent en
    parallèle. Chaque worker attend son tour ; ceux qui arrivent après le premier
    trouvent les migrations déjà appliquées et terminent immédiatement.

    Dans un exe PyInstaller (sys.frozen=True), Alembic ne peut pas trouver env.py
    car les fichiers .py sont compilés en bytecode embarqué. On saute Alembic
    entièrement — _sync_schema_from_models gère la sync de schéma à la place.
    """
    import sys, os
    from alembic.config import Config as AlembicConfig
    from alembic import command as alembic_command

    if getattr(sys, "frozen", False):
        _log.info("Exe PyInstaller — migrations Alembic ignorées (sync via _sync_schema_from_models)")
        return

    ini_path = os.path.join(os.path.dirname(__file__), "alembic.ini")
    alembic_cfg = AlembicConfig(ini_path)

    with engine.connect() as lock_conn:
        # Verrou advisory MySQL — attend jusqu'à 60 s que le worker précédent finisse
        if engine.dialect.name == "mysql":
            got = lock_conn.execute(
                text("SELECT GET_LOCK('pos_alembic_migration', 60)")
            ).scalar()
            if not got:
                _log.warning("Migration lock timeout — un autre worker migre déjà")
                return

        try:
            has_alembic_table = engine.dialect.has_table(lock_conn, "alembic_version")
            if not has_alembic_table:
                _log.info("Nouveau déploiement — stamp Alembic à 'heads'")
                alembic_command.stamp(alembic_cfg, "heads")
            else:
                _log.info("Déploiement existant — alembic upgrade heads")
                try:
                    alembic_command.upgrade(alembic_cfg, "heads")
                except Exception as rev_err:
                    # La révision courante dans alembic_version appartient à une
                    # ancienne chaîne de migrations (ex: top-level alembic/).
                    # On repart de zéro dans cette chaîne : delete + upgrade.
                    _log.warning(
                        "Révision inconnue en DB (%s) — réinitialisation de la chaîne alembic",
                        rev_err,
                    )
                    lock_conn.execute(text("DELETE FROM alembic_version"))
                    lock_conn.commit()
                    try:
                        alembic_command.upgrade(alembic_cfg, "heads")
                    except Exception as retry_err:
                        _log.error(
                            "Échec upgrade après réinitialisation (%s) — stamp à heads",
                            retry_err,
                        )
                        alembic_command.stamp(alembic_cfg, "heads")
        finally:
            if engine.dialect.name == "mysql":
                lock_conn.execute(text("SELECT RELEASE_LOCK('pos_alembic_migration')"))


def _sync_schema_from_models(active_engine=None) -> None:
    """
    Synchronise automatiquement le schéma DB avec les modèles SQLAlchemy :
    inspecte chaque table existante et ajoute toutes les colonnes manquantes.

    Idempotent et exhaustif — résiste au stamp alembic, aux migrations ratées,
    aux nouvelles colonnes ajoutées dans les modèles. Plus aucune liste manuelle
    à maintenir : toute colonne dans un modèle sera présente en DB au prochain
    démarrage, quoi qu'il arrive.
    """
    import api.database as _db_mod
    from sqlalchemy import inspect as _inspect

    _eng = active_engine or _db_mod.engine

    try:
        inspector = _inspect(_eng)
        existing_tables = set(inspector.get_table_names())
    except Exception as exc:
        _log.warning("schema-sync: impossible d'inspecter les tables: %s", exc)
        return

    dialect = _eng.dialect
    added = 0

    with _eng.connect() as conn:
        for table in Base.metadata.sorted_tables:
            if table.name not in existing_tables:
                continue  # table absente — create_all s'en charge

            try:
                db_cols = {c["name"] for c in inspector.get_columns(table.name)}
            except Exception:
                continue

            for col in table.columns:
                if col.name in db_cols or col.primary_key:
                    continue  # déjà présente ou clé primaire

                try:
                    col_type = col.type.compile(dialect=dialect)

                    # Clause NULL / NOT NULL
                    nullable_sql = "" if col.nullable else " NOT NULL"

                    # Clause DEFAULT
                    default_sql = ""
                    if col.server_default is not None:
                        sd_arg = col.server_default.arg
                        # TextClause (sa.text("'val'")) ou chaîne simple
                        raw = sd_arg.text if hasattr(sd_arg, "text") else str(sd_arg)
                        default_sql = f" DEFAULT {raw}"
                    elif not col.nullable:
                        # NOT NULL sans server_default → défaut neutre pour ne pas bloquer
                        t = col_type.upper()
                        if any(k in t for k in ("INT", "BOOL", "DECIMAL", "FLOAT", "DOUBLE", "NUMERIC")):
                            default_sql = " DEFAULT 0"
                        elif "DATETIME" in t or "TIMESTAMP" in t:
                            default_sql = " DEFAULT CURRENT_TIMESTAMP"
                        else:
                            default_sql = " DEFAULT ''"

                    stmt = (
                        f"ALTER TABLE `{table.name}` "
                        f"ADD COLUMN `{col.name}` {col_type}{nullable_sql}{default_sql}"
                    )
                    conn.execute(text(stmt))
                    conn.commit()
                    added += 1
                    _log.info("schema-sync: + %s.%s %s", table.name, col.name, col_type)
                except Exception:
                    conn.rollback()  # colonne déjà présente ou type incompatible — ignoré

    if added:
        _log.info("schema-sync: %d colonne(s) ajoutée(s)", added)


# Gardé pour compatibilité — remplacé par _sync_schema_from_models()
def _ensure_schema_patches() -> None:
    pass



def _ensure_default_warehouse(db, tenant_id: str) -> None:
    """
    Serveurs cloud-linked : les dépôts viennent du cloud via sync pull uniquement.
    Ne crée rien en local. Si installer_wh_id est connu, marque juste le bon
    dépôt comme is_default s'il existe déjà (après un premier pull).
    Serveurs standalone (sans cloud_sync_url) : crée un dépôt par défaut si absent.
    """
    from api.models.Warehouse import Warehouse as WarehouseModel
    from api.core.config import settings as _cfg, load_ini_config as _lini
    try:
        _ini_cfg = _lini()
        _is_cloud_linked = bool(
            (_ini_cfg.get("CLOUD_SYNC_URL") or _ini_cfg.get("cloud_sync_url") or "").strip()
        )

        if _is_cloud_linked:
            # Dépôts viennent du cloud seulement — juste aligner is_default si possible
            installer_wh_id = _cfg.INSTALLER_WAREHOUSE_ID or None
            if installer_wh_id:
                wh = db.query(WarehouseModel).filter(
                    WarehouseModel.id == installer_wh_id,
                    WarehouseModel.tenant_id == tenant_id,
                ).first()
                if wh and not wh.is_default:
                    db.query(WarehouseModel).filter(
                        WarehouseModel.tenant_id == tenant_id,
                        WarehouseModel.is_default == True,  # noqa: E712
                    ).update({"is_default": False})
                    wh.is_default = True
                    db.commit()
            return  # Jamais de création locale pour un serveur cloud-linked

        # Serveur standalone — crée le dépôt par défaut seulement si absent
        exists = db.query(WarehouseModel).filter(
            WarehouseModel.tenant_id == tenant_id
        ).first()
        if not exists:
            wh = WarehouseModel(
                tenant_id=tenant_id,
                name="Depot principal",
                is_default=True,
                is_active=True,
            )
            db.add(wh)
            db.commit()
            _log.info("Depot par defaut cree pour le tenant %s (standalone)", tenant_id)
            from api.services import config_service as _cfg_svc
            _cfg_svc.create_for_warehouse(db, tenant_id, wh.id)
    except Exception as exc:
        _log.warning("_ensure_default_warehouse: %s", exc)


def _ensure_cloud_admin(db, local_tid: str) -> None:
    """
    Garantit qu'un compte superadmin existe dans PlatformConfig ET dans users.
    Priorité : PlatformConfig (DB) > settings (env/ini) > auto-génération.
    Idempotent — ne fait rien si tout est déjà en place.

    Skippé si ce serveur est déjà configuré comme serveur tenant local
    (cloud_sync_url présent dans INI) — dans ce cas le tenant crée son propre
    compte admin via connect_tenant.
    """
    import secrets
    from api.models.PlatformConfig import PlatformConfig
    from api.models.User import User
    from api.services.auth import get_password_hash
    from api.core.config import settings, load_ini_config

    # Si le serveur est lié à un tenant cloud (cloud_sync_url configuré),
    # ne pas créer de superadmin plateforme — le compte tenant suffira.
    ini = load_ini_config()
    if ini.get("CLOUD_SYNC_URL"):
        return

    # ── 1. PlatformConfig singleton ──────────────────────────────────────────
    cfg = db.query(PlatformConfig).first()
    if not cfg:
        cfg = PlatformConfig()
        db.add(cfg)
        db.flush()

    # ── 2. Résoudre les credentials effectifs ────────────────────────────────
    admin_email = cfg.admin_email or settings.ADMIN_EMAIL or ""
    admin_hash  = cfg.admin_password_hash or settings.ADMIN_PASSWORD_HASH or ""
    raw_password: str | None = None

    if not admin_email:
        # Première initialisation — génération automatique
        raw_password = secrets.token_urlsafe(12)
        admin_email  = settings.ADMIN_EMAIL or "admin@posconnect.ht"
        admin_hash   = get_password_hash(raw_password)
        cfg.admin_email         = admin_email
        cfg.admin_password_hash = admin_hash
        db.commit()
        _log.info("=" * 62)
        _log.info("  PREMIÈRE INITIALISATION — IDENTIFIANTS SUPERADMIN GÉNÉRÉS")
        _log.info("  Email    : %s", admin_email)
        _log.info("  Password : %s", raw_password)
        _log.info("  → Changez ce mot de passe via le panel /admin")
        _log.info("=" * 62)
    else:
        # Sync env/ini → DB si DB était vide (ex: migration depuis ancienne version)
        changed = False
        if not cfg.admin_email:
            cfg.admin_email = admin_email
            changed = True
        if not cfg.admin_password_hash:
            cfg.admin_password_hash = admin_hash
            changed = True
        if changed:
            db.commit()

    # ── 3. Mettre à jour settings en mémoire (auth endpoint lit settings) ───
    settings.ADMIN_EMAIL         = admin_email
    settings.ADMIN_PASSWORD_HASH = admin_hash

    # ── 4. Créer l'utilisateur admin dans users si absent ───────────────────
    existing = db.query(User).filter(
        (User.username == "admin") | (User.email == admin_email)
    ).first()
    if existing:
        return

    # Créer le user avec les credentials EXISTANTS — ne jamais régénérer le mot de passe
    try:
        admin_user = User(
            tenant_id=local_tid,
            fname="Super",
            lname="Admin",
            username="admin",
            phone=None,
            email=admin_email,
            password=admin_hash,
            roles=["admin"],
            permissions=["all"],
            must_change_password=True,
        )
        db.add(admin_user)
        db.commit()
        _log.info("Utilisateur admin créé dans users (tenant: %s)", local_tid)
    except Exception as exc:
        db.rollback()
        _log.warning("Impossible de créer l'utilisateur admin dans users : %s", exc)


def _ensure_db_ready():
    """
    Teste la connexion DB au démarrage.
    Si MySQL est configuré mais inaccessible, bascule automatiquement sur SQLite
    et met à jour le moteur global — évite un crash non géré au premier démarrage.
    """
    import api.database as _db_module
    from api.core.config import settings as _s

    try:
        with _db_module.engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return _db_module.engine  # connexion OK
    except Exception as exc:
        if _s.DB_TYPE != "sqlite":
            _log.warning(
                "⚠️  Impossible de joindre MySQL (%s). "
                "Basculement automatique sur SQLite (pos_connect.db). "
                "Configurez pos_server.ini [database] type=sqlite pour éviter ce message.",
                exc,
            )
            # Recréer le moteur en mode SQLite
            # Chemin absolu : ProgramData sur Windows, répertoire courant ailleurs
            import os as _os
            from pathlib import Path as _Path
            from sqlalchemy import create_engine
            from sqlalchemy.orm import sessionmaker
            if _os.name == "nt":
                _data = _Path(_os.environ.get("PROGRAMDATA", "C:\\ProgramData")) / "POS_Connect"
                _data.mkdir(parents=True, exist_ok=True)
                _sqlite_path = str(_data / "pos_connect.db")
                # Supprimer l'attribut lecture-seule et s'assurer que SYSTEM peut écrire.
                # Nécessaire quand le fichier a été créé par une installation précédente
                # avec des permissions restrictives (errno SQLITE_READONLY au démarrage).
                try:
                    import stat as _stat
                    import subprocess as _sp
                    if _os.path.exists(_sqlite_path):
                        _mode = _os.stat(_sqlite_path).st_mode
                        if not (_mode & _stat.S_IWRITE):
                            _os.chmod(_sqlite_path, _mode | _stat.S_IWRITE)
                    # Accorder SYSTEM + Administrateurs en écriture sur tout le dossier
                    _sp.run(
                        ["icacls", str(_data),
                         "/grant", "SYSTEM:(OI)(CI)F",
                         "/grant", "Administrators:(OI)(CI)F",
                         "/T", "/C", "/Q"],
                        capture_output=True, timeout=10,
                    )
                except Exception as _perm_exc:
                    _log.warning("SQLite permission fix échoué : %s", _perm_exc)
            else:
                _sqlite_path = "./pos_connect.db"
            sqlite_url = f"sqlite:///{_sqlite_path}"
            new_engine = create_engine(
                sqlite_url,
                connect_args={"check_same_thread": False, "timeout": 15},
            )

            from sqlalchemy import event as _sa_event
            @_sa_event.listens_for(new_engine, "connect")
            def _set_sqlite_pragma(dbapi_conn, _):
                cursor = dbapi_conn.cursor()
                cursor.execute("PRAGMA journal_mode=WAL")
                cursor.execute("PRAGMA busy_timeout=15000")
                cursor.execute("PRAGMA foreign_keys=ON")
                cursor.close()

            _db_module.engine       = new_engine
            _db_module.SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=new_engine)
            _s.DB_TYPE = "sqlite"
            return new_engine
        else:
            _log.error("❌  Base de données SQLite inaccessible : %s", exc)
            raise


def _ensure_sqlite_writable(engine) -> bool:
    """
    Vérifie si le fichier SQLite est réellement accessible en écriture.
    os.access() vérifie les ACL Windows mais PAS l'attribut fichier read-only
    (FILE_ATTRIBUTE_READONLY), ce qui peut tromper SQLite. On tente une écriture
    réelle plutôt que de se fier à os.access().
    """
    import os, stat as _stat
    import subprocess as _sp
    from api.core.config import settings as _s
    if _s.DB_TYPE != "sqlite":
        return True

    db_path = str(engine.url.database or "")
    if not db_path or db_path == ":memory:":
        return True

    # Toujours tenter chmod + icacls avant le test réel.
    # chmod sur Windows efface l'attribut FILE_ATTRIBUTE_READONLY, os.access ne le fait pas.
    try:
        if os.path.exists(db_path):
            current_mode = os.stat(db_path).st_mode
            os.chmod(db_path, current_mode | _stat.S_IWRITE | _stat.S_IWGRP | _stat.S_IWOTH)
    except Exception:
        pass

    if os.name == "nt":
        try:
            _sp.run(
                ["icacls", db_path, "/grant", "SYSTEM:(F)", "/grant", "Administrators:(F)"],
                capture_output=True, timeout=5,
            )
        except Exception:
            pass

    # Test d'écriture réelle : seule garantie fiable sur Windows.
    try:
        with open(db_path, "ab"):
            pass
        return True
    except OSError:
        pass

    _log.warning(
        "⚠️  %s est en lecture seule — create_all ignoré. "
        "Corrigez avec : icacls \"%s\" /grant SYSTEM:(F)",
        db_path, db_path,
    )
    return False


@app.on_event("startup")
def on_startup():
    from api.database import SessionLocal
    from api.models.Role import Role as RoleModel
    from api.core.permissions import ROLE_PERMISSIONS, load_roles_from_db

    # 0. Vérifie la connexion DB — bascule sur SQLite si MySQL absent
    _active_engine = _ensure_db_ready()

    # 0b. Vérifie si SQLite est accessible en écriture (une seule fois, avant tout)
    _db_writable = _ensure_sqlite_writable(_active_engine)

    # 1. Crée les tables manquantes (nouveau déploiement ou nouvelle table ajoutée)
    if _db_writable:
        try:
            Base.metadata.create_all(bind=_active_engine)
        except Exception as _cae:
            _log.error(
                "❌ create_all() échoué (%s). "
                "Vérifiez les permissions de la base de données. "
                "MySQL: pos_server.ini [database] type=mysql. "
                "SQLite: icacls pos_connect.db /grant SYSTEM:(F)",
                _cae,
            )
            _log.info("Démarrage en mode dégradé — schéma non synchronisé.")
        else:
            # 2. Applique les migrations Alembic (ou stamp si premier démarrage)
            try:
                _run_alembic_migrations()
            except Exception as exc:
                _log.warning("Alembic migration warning: %s", exc)
            # 2b. Synchronise automatiquement le schéma DB avec les modèles SQLAlchemy
            _sync_schema_from_models(_active_engine)
    else:
        _log.info("DB lecture seule — create_all / migrations ignorés.")

    import api.database as _db_module
    db = _db_module.SessionLocal()
    try:
        # 3. Tenant_id — lu depuis l'INI si déjà lié au cloud, sinon None
        from api.core.config import load_ini_config as _load_ini
        _ini = _load_ini()
        local_tid: str | None = (_ini.get("CLOUD_TENANT_ID") or _ini.get("cloud_tenant_id") or "").strip() or None

        if _db_writable:
            # 4. Superadmin — auto-génère les credentials si absent, crée le user
            _ensure_cloud_admin(db, local_tid)
            # 5. Dépôt par défaut — crée "Depot principal" si aucun dépôt n'existe
            _ensure_default_warehouse(db, local_tid)
            # 6. Seed/sync built-in roles — crée ou met à jour les permissions
            for rd in _BUILTIN_ROLES:
                perms = rd["permissions"] if rd["permissions"] is not None \
                    else list(ROLE_PERMISSIONS.get(rd["name"], set()))
                existing = db.query(RoleModel).filter(RoleModel.name == rd["name"]).first()
                if not existing:
                    db.add(RoleModel(
                        name=rd["name"],
                        label=rd["label"],
                        color=rd["color"],
                        is_builtin=True,
                        permissions=perms,
                    ))
                else:
                    existing.label       = rd["label"]
                    existing.color       = rd["color"]
                    existing.permissions = perms
            db.commit()

        # Charge les rôles en mémoire — lecture seule, toujours possible
        try:
            load_roles_from_db(db.query(RoleModel).all())
        except Exception as _load_exc:
            _log.warning("Impossible de charger les rôles depuis la DB : %s", _load_exc)
    except Exception:
        _log.exception("ERREUR CRITIQUE on_startup — le serveur ne peut pas démarrer")
        raise
    finally:
        db.close()

_AUTO_SYNC_INTERVAL = 300   # max secondes entre deux cycles (5 min)
_SYNC_DEBOUNCE      = 5     # secondes d'attente après signal pour batcher les écritures rapides
_auto_sync_task: asyncio.Task | None = None
_sync_event = asyncio.Event()           # signalé après toute écriture locale


def signal_pending_sync() -> None:
    """Appeler après toute écriture locale — réveille le loop de sync immédiatement."""
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            loop.call_soon_threadsafe(_sync_event.set)
    except RuntimeError:
        pass


def _do_sync_cycle():
    """Blocking sync cycle — run in thread via asyncio.to_thread."""
    from api.services.local_sync_service import _load_sync_credentials, run_sync
    from api.database import SessionLocal
    url, token, enabled = _load_sync_credentials()
    if not (enabled and url and token):
        return None
    db = SessionLocal()
    try:
        return run_sync(db)
    finally:
        db.close()


async def _auto_sync_loop():
    """
    Background loop — tourne toutes les 5 min au maximum.
    Se réveille IMMÉDIATEMENT (après un debounce de 5 s) dès qu'une écriture
    locale signale _sync_event, pour une sync quasi-temps-réel.
    """
    _slog = logging.getLogger("pos.autosync")
    await asyncio.sleep(30)  # attendre que le serveur soit prêt
    while True:
        try:
            result = await asyncio.to_thread(_do_sync_cycle)
            if result is None:
                pass  # pas encore configuré
            elif result.get("ok"):
                pushed_total = sum(result.get("pushed", {}).values())
                pulled_total = sum(result.get("pulled", {}).values())
                if pushed_total or pulled_total:
                    _slog.info("Sync OK — pushed=%d pulled=%d", pushed_total, pulled_total)
            else:
                _slog.warning("Sync partiel — erreurs: %s", result.get("errors"))
        except Exception as exc:
            _slog.error("Sync loop error: %s", exc)

        # Attendre le prochain déclencheur : écriture locale OU timeout 5 min
        _sync_event.clear()
        try:
            await asyncio.wait_for(_sync_event.wait(), timeout=_AUTO_SYNC_INTERVAL)
            # Écriture détectée — debounce pour regrouper les transactions rapides
            await asyncio.sleep(_SYNC_DEBOUNCE)
        except asyncio.TimeoutError:
            pass  # cycle régulier 5 min


@app.on_event("startup")
async def start_auto_sync():
    global _auto_sync_task
    # Auto-heal: if cloud_sync_url is set but billing_url is missing, fill it in.
    # Happens when the server was configured with an older installer that didn't write billing_url.
    from api.core.config import load_ini_config, write_ini_config, settings as _s
    _ini = load_ini_config()
    _sync_url = _ini.get("CLOUD_SYNC_URL") or _ini.get("cloud_sync_url") or ""
    _bill_url = _ini.get("BILLING_URL") or _ini.get("billing_url") or ""
    if _sync_url and not _bill_url:
        write_ini_config({"billing_url": _sync_url})
        _s.BILLING_URL = _sync_url
        _log.info("Auto-heal: billing_url set to %s (from cloud_sync_url)", _sync_url)

    _auto_sync_task = asyncio.create_task(_auto_sync_loop())


def restart_auto_sync():
    """Call this after sync/configure to restart the loop immediately."""
    global _auto_sync_task
    if _auto_sync_task and not _auto_sync_task.done():
        _auto_sync_task.cancel()
    _auto_sync_task = asyncio.create_task(_auto_sync_loop())


@app.get("/health", include_in_schema=False)
async def health_root():
    return {"status": "ok"}


# ── Flutter web SPA (servi uniquement si le dossier existe) ──────────────────
# Le build Flutter web est copié dans WEB_DIR (défaut: "web/") à côté du serveur.
# flutter build web --release  →  frontend/build/web/  →  copier dans web/
import os as _os
from pathlib import Path as _Path

_web_dir = _Path(_settings_cors.WEB_DIR or "web")
if _web_dir.exists() and _web_dir.is_dir():
    _NO_CACHE = {
        "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
        "Pragma": "no-cache",
    }

    # Routes spéciales avant le mount StaticFiles : empêchent le navigateur
    # de servir une version obsolète après un déploiement.
    @app.get("/", include_in_schema=False)
    @app.get("/index.html", include_in_schema=False)
    async def _serve_index():
        return FileResponse(str(_web_dir / "index.html"), headers=_NO_CACHE)

    @app.get("/flutter_service_worker.js", include_in_schema=False)
    async def _serve_sw():
        return FileResponse(str(_web_dir / "flutter_service_worker.js"), headers=_NO_CACHE)

    @app.get("/flutter_bootstrap.js", include_in_schema=False)
    async def _serve_bootstrap():
        return FileResponse(str(_web_dir / "flutter_bootstrap.js"), headers=_NO_CACHE)

    # Monté EN DERNIER — les routes API prennent toujours la priorité.
    app.mount("/", StaticFiles(directory=str(_web_dir), html=True), name="web")
    _log.info("Flutter web SPA servi depuis : %s", _web_dir.resolve())

@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    return {}


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = {}
    for err in exc.errors():
        field = err["loc"][-1]
        message = err["msg"]
        errors[field] = message

    return JSONResponse(
        status_code=422,
        content={
            "message": "Erreur de validation",
            "errors": errors
        }
    )

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"message": exc.detail}
    )



@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    _logger = logging.getLogger("pos.api")
    _logger.error("Unhandled exception on %s %s: %s", request.method, request.url.path, exc, exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"message": "Erreur interne du serveur"},
    )



# @app.get("/")
# def root():
#     return {"message": "Hello POS"}


#   python.exe -m  uvicorn api.main:app --reload
