
import asyncio
import logging
import os
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
from api.routes import returns, sales, purchases, user, category, customer, product, login, supplier, auth, stock, purchases_receive, payments, debts, config, discount
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
from api.routes import client_sabotage as client_sabotage_router
from api.routes import depot as depot_router
from api.routes import retrait as retrait_router
from api.routes import entrepot as entrepot_router
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
from api.models.InstallationCode import InstallationCode as _InstallationCode  # noqa: F401 — ensures table creation
from fastapi.staticfiles import StaticFiles
from fastapi.encoders import jsonable_encoder

from api.core.config import settings as _settings_docs

# /docs, /redoc, /openapi.json désactivés par défaut — voir ENABLE_API_DOCS
# (config.py) : un serveur local exposé sur le LAN ne doit pas exposer une
# console d'appel API interactive publiquement.
app = FastAPI(
    docs_url="/docs" if _settings_docs.ENABLE_API_DOCS else None,
    redoc_url="/redoc" if _settings_docs.ENABLE_API_DOCS else None,
    openapi_url="/openapi.json" if _settings_docs.ENABLE_API_DOCS else None,
)

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
    allow_origin_regex=_settings_cors.CORS_ORIGIN_REGEX or None,
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
app.include_router(discount.router)
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
app.include_router(client_sabotage_router.router)
app.include_router(depot_router.router)
app.include_router(retrait_router.router)
app.include_router(entrepot_router.router)

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
                except KeyError as rev_err:
                    # Graphe de révisions cassé (fichier manquant/ID inconnu) —
                    # NE PAS effacer alembic_version, juste ignorer.
                    _log.error(
                        "Graphe alembic corrompu (%s) — migrations ignorées, schéma géré par _sync_schema_from_models",
                        rev_err,
                    )
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

    Protégé par le même verrou advisory MySQL que _run_alembic_migrations —
    sans ça, plusieurs workers Gunicorn démarrant en parallèle peuvent lancer
    des ALTER TABLE concurrents sur la même colonne (l'un réussit, l'autre
    échoue avec une erreur qui n'est pas un simple "colonne déjà présente"
    et se retrouve silencieusement avalée, ce qui a masqué l'échec réel
    d'ajout de users.permissions_version en production).
    """
    import api.database as _db_mod
    from sqlalchemy import inspect as _inspect

    _eng = active_engine or _db_mod.engine

    lock_conn = None
    got_lock = True
    if _eng.dialect.name == "mysql":
        lock_conn = _eng.connect()
        got_lock = lock_conn.execute(text("SELECT GET_LOCK('pos_schema_sync', 60)")).scalar()
        if not got_lock:
            _log.warning("schema-sync: verrou occupé par un autre worker — ignoré ce cycle")
            lock_conn.close()
            return

    try:
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
                        elif getattr(col, "default", None) is not None and getattr(col.default, "is_scalar", False):
                            # default= (Python, appliqué par l'ORM à l'INSERT) — sans ce
                            # cas, une colonne ADD COLUMN sur une table déjà existante
                            # ignorait ce default et retombait sur le neutre ci-dessous
                            # (0 / '' / CURRENT_TIMESTAMP), même quand le modèle en
                            # déclarait un autre (ex: PlatformConfig.annual_discount_pct
                            # default=20 → colonne ajoutée avec DEFAULT 0).
                            arg = col.default.arg
                            if isinstance(arg, bool):
                                default_sql = f" DEFAULT {1 if arg else 0}"
                            elif isinstance(arg, (int, float)):
                                default_sql = f" DEFAULT {arg}"
                            elif isinstance(arg, str):
                                default_sql = " DEFAULT '{}'".format(arg.replace("'", "''"))
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
                    except Exception as col_exc:
                        conn.rollback()
                        _log.warning(
                            "schema-sync: échec ajout %s.%s (%s) — colonne probablement déjà présente",
                            table.name, col.name, col_exc,
                        )

        if added:
            _log.info("schema-sync: %d colonne(s) ajoutée(s)", added)
    finally:
        if lock_conn is not None:
            try:
                if got_lock:
                    lock_conn.execute(text("SELECT RELEASE_LOCK('pos_schema_sync')"))
            finally:
                lock_conn.close()


# Gardé pour compatibilité — remplacé par _sync_schema_from_models()
def _ensure_schema_patches() -> None:
    pass


def _fix_register_billing_date_columns(active_engine=None) -> None:
    """
    Sur les installations PyInstaller (Alembic ignoré), pos_registers.trial_ends_at,
    subscription_started_at et subscription_ends_at peuvent rester en DATETIME alors
    que le modèle attend TEXT(600) pour les tokens Fernet.

    Cette fonction :
      1. Détecte si les colonnes sont encore en DATETIME
      2. Lit et chiffre les valeurs existantes avec Fernet (per-register key)
      3. Remplace la colonne DATETIME par TEXT(600)
    Idempotent — sans effet si les colonnes sont déjà TEXT.
    """
    import api.database as _db_mod
    from sqlalchemy import text as _text, inspect as _inspect

    _eng = active_engine or _db_mod.engine
    if _eng.dialect.name != "mysql":
        return  # SQLite n'a pas de types stricts, pas de problème

    _COLS = ("trial_ends_at", "subscription_started_at", "subscription_ends_at")

    with _eng.connect() as conn:
        for col in _COLS:
            try:
                row = conn.execute(_text(
                    "SELECT DATA_TYPE FROM information_schema.columns "
                    "WHERE table_schema = DATABASE() "
                    "AND table_name = 'pos_registers' AND column_name = :c"
                ), {"c": col}).fetchone()
                if not row:
                    continue  # colonne absente — create_all s'en charge
                if row[0].lower() in ("text", "mediumtext", "longtext", "varchar"):
                    continue  # déjà TEXT, rien à faire

                _log.info("schema-fix: pos_registers.%s est DATETIME — conversion en TEXT(600)", col)

                # 1. Colonne temporaire TEXT pour accueillir les tokens Fernet
                tmp = f"{col}_enc"
                has_tmp = conn.execute(_text(
                    "SELECT COUNT(*) FROM information_schema.columns "
                    "WHERE table_schema = DATABASE() "
                    "AND table_name = 'pos_registers' AND column_name = :c"
                ), {"c": tmp}).scalar()
                if not has_tmp:
                    conn.execute(_text(
                        f"ALTER TABLE pos_registers ADD COLUMN `{tmp}` TEXT(600)"
                    ))
                    conn.commit()

                # 2. Chiffrer les valeurs DATETIME existantes dans la colonne temp
                from api.core.billing_crypto import encrypt_register_date as _enc_date
                from datetime import timezone as _tz
                rows = conn.execute(_text(
                    f"SELECT id, `{col}` FROM pos_registers WHERE `{col}` IS NOT NULL"
                )).fetchall()
                for reg_id, dt in rows:
                    if dt is None:
                        continue
                    try:
                        if hasattr(dt, "tzinfo") and dt.tzinfo is None:
                            dt = dt.replace(tzinfo=_tz.utc)
                        token = _enc_date(dt, str(reg_id))
                        conn.execute(_text(
                            f"UPDATE pos_registers SET `{tmp}` = :tok WHERE id = :id"
                        ), {"tok": token, "id": str(reg_id)})
                    except Exception as _enc_exc:
                        _log.warning("schema-fix: chiffrement %s pour %s: %s", col, reg_id, _enc_exc)
                conn.commit()

                # 3. Supprimer l'ancienne colonne DATETIME
                conn.execute(_text(f"ALTER TABLE pos_registers DROP COLUMN `{col}`"))
                conn.commit()

                # 4. Renommer la colonne temporaire → nom original
                conn.execute(_text(
                    f"ALTER TABLE pos_registers CHANGE COLUMN `{tmp}` `{col}` TEXT(600)"
                ))
                conn.commit()

                _log.info("schema-fix: pos_registers.%s converti DATETIME → TEXT(600)", col)
            except Exception as exc:
                try:
                    conn.rollback()
                except Exception:
                    pass
                _log.warning("schema-fix pos_registers.%s: %s", col, exc)


def _migrate_per_tenant_unique(active_engine=None) -> None:
    """
    Convertit les contraintes UNIQUE globales en contraintes composées (col, tenant_id).
    Ne s'exécute que sur MySQL (multi-tenant) ; SQLite est mono-tenant, pas besoin.
    Idempotent : ignore silencieusement les contraintes déjà converties.
    """
    import api.database as _db_mod
    from sqlalchemy import inspect as _inspect

    _eng = active_engine or _db_mod.engine
    if _eng.dialect.name != "mysql":
        return

    # (table, colonne, colonne_scope, nom_nouvelle_contrainte)
    # colonne_scope est "tenant_id" pour la plupart (unicité par tenant), mais
    # "warehouse_id" pour les caisses (unicité par dépôt, pas par tenant entier).
    _TARGETS = [
        ("sales",           "reference", "tenant_id",    "uq_sale_ref_tenant"),
        ("purchases",       "reference", "tenant_id",    "uq_purchase_ref_tenant"),
        ("products",        "name",      "tenant_id",    "uq_product_name_tenant"),
        ("products",        "barcode",   "tenant_id",    "uq_product_barcode_tenant"),
        ("users",           "username",  "tenant_id",    "uq_user_username_tenant"),
        ("users",           "email",     "tenant_id",    "uq_user_email_tenant"),
        ("users",           "phone",     "tenant_id",    "uq_user_phone_tenant"),
        ("invoices",        "reference", "tenant_id",    "uq_invoice_ref_tenant"),
        ("proformas",       "reference", "tenant_id",    "uq_proforma_ref_tenant"),
        ("employee_loans",  "reference", "tenant_id",    "uq_employee_loan_ref_tenant"),
        ("payroll_periods", "reference", "tenant_id",    "uq_payroll_period_ref_tenant"),
        ("warehouses",      "name",      "tenant_id",    "uq_warehouse_name_tenant"),
        ("pos_registers",   "name",      "warehouse_id", "uq_register_name_warehouse"),
    ]

    try:
        inspector = _inspect(_eng)
        existing_tables = set(inspector.get_table_names())
    except Exception as exc:
        _log.warning("per-tenant-unique migration: impossible d'inspecter: %s", exc)
        return

    with _eng.connect() as conn:
        for table, col, scope_col, new_name in _TARGETS:
            if table not in existing_tables:
                continue
            try:
                indexes = inspector.get_indexes(table)

                # Déjà migré ?
                if any(idx["name"] == new_name for idx in indexes):
                    continue

                # Supprimer les index UNIQUE mono-colonne sur cette colonne
                for idx in indexes:
                    if idx.get("unique") and idx.get("column_names") == [col]:
                        old = idx["name"]
                        try:
                            conn.execute(text(f"ALTER TABLE `{table}` DROP INDEX `{old}`"))
                            conn.commit()
                            _log.info("per-tenant-unique: supprimé %s.%s (%s)", table, col, old)
                        except Exception as drop_exc:
                            conn.rollback()
                            _log.warning("per-tenant-unique: DROP INDEX %s.%s: %s", table, old, drop_exc)

                # Ajouter la contrainte composée
                try:
                    conn.execute(text(
                        f"ALTER TABLE `{table}` "
                        f"ADD UNIQUE KEY `{new_name}` (`{col}`, `{scope_col}`)"
                    ))
                    conn.commit()
                    _log.info("per-tenant-unique: + %s(%s, %s) → %s", table, col, scope_col, new_name)
                except Exception as add_exc:
                    conn.rollback()
                    _log.warning("per-tenant-unique: ADD KEY %s.%s: %s", table, new_name, add_exc)
            except Exception as exc:
                _log.warning("per-tenant-unique: %s.%s: %s", table, col, exc)


def _backfill_haiti_local_time(active_engine=None) -> None:
    """
    Migration ponctuelle : les colonnes DateTime métier (created_at/updated_at,
    dates de trial/abonnement, etc.) étaient historiquement calculées en UTC
    (datetime.now(timezone.utc)). Le code utilise désormais now_local() (heure
    locale Haiti, naïve, DST-aware via ZoneInfo). Les lignes déjà en base
    contiennent donc des valeurs UTC — cette fonction les convertit vers la
    nouvelle convention.

    Haiti applique un DST (UTC-5 en hiver, UTC-4 en été) : le décalage n'est
    PAS uniforme selon la date de la ligne. La conversion se fait donc valeur
    par valeur via ZoneInfo (dt_utc.astimezone(HAITI_TZ)), pas par un simple
    "-5h" SQL — l'ancienne valeur naïve est réinterprétée comme UTC puis
    reconvertie.

    Idempotent via une table marqueur (tz_migration_marker) — ne s'exécute
    qu'une seule fois par base. Les champs Fernet (PosRegister, BillingPayment)
    sont convertis séparément : un token legacy se déchiffre en datetime aware
    (offset encore présent dans le JSON chiffré) alors qu'un token déjà migré
    se déchiffre en naïf — ce qui sert de garde-fou supplémentaire par valeur.
    """
    import api.database as _db_mod
    from datetime import datetime, timezone as _dt_timezone
    from sqlalchemy import text as _text, inspect as _inspect
    from api.core.dt_coerce import now_local, HAITI_TZ

    def _to_haiti(naive_utc_dt):
        """Réinterprète un datetime naïf (ancienne convention UTC) en heure Haiti naïve.

        SQLite renvoie parfois une string via une requête texte brute plutôt
        qu'un objet datetime déjà parsé (contrairement à PyMySQL).
        """
        if naive_utc_dt is None:
            return None
        if isinstance(naive_utc_dt, str):
            naive_utc_dt = datetime.fromisoformat(naive_utc_dt.replace(" ", "T"))
        aware = naive_utc_dt.replace(tzinfo=_dt_timezone.utc)
        return aware.astimezone(HAITI_TZ).replace(tzinfo=None)

    _eng = active_engine or _db_mod.engine
    dialect = _eng.dialect.name

    with _eng.connect() as conn:
        conn.execute(_text(
            "CREATE TABLE IF NOT EXISTS tz_migration_marker ("
            "id INTEGER PRIMARY KEY, applied_at VARCHAR(30))"
        ))
        conn.commit()
        already = conn.execute(_text("SELECT COUNT(*) FROM tz_migration_marker")).scalar()
        if already:
            return  # déjà exécuté sur cette base

        _log.info("tz-backfill: conversion des colonnes DateTime existantes (UTC → Haiti local, DST-aware)")

        try:
            inspector = _inspect(_eng)
            existing_tables = set(inspector.get_table_names())
        except Exception as exc:
            _log.warning("tz-backfill: impossible d'inspecter le schéma: %s", exc)
            return

        # Colonnes created_at/updated_at de tous les modèles (héritées de UUIDBase)
        cols_by_table: dict[str, set[str]] = {}
        for table_name, table in Base.metadata.tables.items():
            if table_name not in existing_tables:
                continue
            for col_name in ("created_at", "updated_at"):
                if col_name in table.columns:
                    cols_by_table.setdefault(table_name, set()).add(col_name)

        # Colonnes DateTime métier explicites hors created_at/updated_at
        _EXTRA_COLS = {
            "purchases":          {"ordered_at", "received_at"},
            "purchase_receipts":  {"received_at"},
            "cashier_sessions":   {"opened_at", "closed_at"},
            "pos_registers":      {"last_seen"},
            "tenants":            {"trial_ends_at", "subscription_started_at",
                                    "subscription_ends_at", "last_warning_sent_at"},
            "billing_payments":   {"paid_at"},
            "billing_extras":     {"started_at", "ended_at"},
            "payroll_entries":    {"paid_at"},
            "sync_state":         {"last_push_at", "last_pull_at"},
            "installation_codes": {"created_at"},
        }
        for table_name, extra in _EXTRA_COLS.items():
            if table_name in existing_tables:
                cols_by_table.setdefault(table_name, set()).update(extra)

        _quote = '`' if dialect == "mysql" else '"'
        for table_name, cols in cols_by_table.items():
            for col in cols:
                q = _quote
                try:
                    rows = conn.execute(_text(
                        f"SELECT id, {q}{col}{q} FROM {q}{table_name}{q} WHERE {q}{col}{q} IS NOT NULL"
                    )).fetchall()
                    params = []
                    for row_id, val in rows:
                        if val is None:
                            continue
                        params.append({"id": row_id, "val": _to_haiti(val)})
                    if params:
                        conn.execute(_text(
                            f"UPDATE {q}{table_name}{q} SET {q}{col}{q} = :val WHERE id = :id"
                        ), params)
                    conn.commit()
                except Exception as exc:
                    conn.rollback()
                    _log.warning("tz-backfill: %s.%s: %s", table_name, col, exc)

        # ── Champs Fernet chiffrés : décrypter (ancien format aware) → conversion Haiti → ré-encrypter
        try:
            from api.core.billing_crypto import (
                try_decrypt_register_date, encrypt_register_date,
                try_decrypt_date, encrypt_date,
            )
            if "pos_registers" in existing_tables:
                _REG_COLS = ("trial_ends_at", "subscription_started_at", "subscription_ends_at")
                rows = conn.execute(_text(
                    "SELECT id, trial_ends_at, subscription_started_at, subscription_ends_at "
                    "FROM pos_registers"
                )).fetchall()
                for reg_id, *tokens in rows:
                    for col, token in zip(_REG_COLS, tokens):
                        if not token:
                            continue
                        dt = try_decrypt_register_date(token, reg_id)
                        if dt is None or dt.tzinfo is None:
                            continue  # déjà au nouveau format (naïf) — rien à faire
                        shifted = dt.astimezone(HAITI_TZ).replace(tzinfo=None)
                        new_token = encrypt_register_date(shifted, reg_id)
                        conn.execute(_text(
                            f"UPDATE pos_registers SET `{col}` = :tok WHERE id = :id"
                        ), {"tok": new_token, "id": reg_id})
                conn.commit()

            if "billing_payments" in existing_tables:
                rows = conn.execute(_text(
                    "SELECT id, tenant_id, period_start, period_end FROM billing_payments"
                )).fetchall()
                for pid, tenant_id, p_start, p_end in rows:
                    updates = {}
                    for col, token in (("period_start", p_start), ("period_end", p_end)):
                        if not token:
                            continue
                        dt = try_decrypt_date(token, tenant_id)
                        if dt is None or dt.tzinfo is None:
                            continue
                        shifted = dt.astimezone(HAITI_TZ).replace(tzinfo=None)
                        updates[col] = encrypt_date(shifted, tenant_id)
                    if updates:
                        set_clause = ", ".join(f"`{c}` = :{c}" for c in updates)
                        conn.execute(_text(
                            f"UPDATE billing_payments SET {set_clause} WHERE id = :id"
                        ), {**updates, "id": pid})
                conn.commit()
        except Exception as exc:
            conn.rollback()
            _log.warning("tz-backfill: champs Fernet: %s", exc)

        conn.execute(_text(
            "INSERT INTO tz_migration_marker (id, applied_at) VALUES (1, :now)"
        ), {"now": now_local().isoformat()})
        conn.commit()
        _log.info("tz-backfill: terminé.")


def _normalize_sale_status_casing(active_engine=None) -> None:
    """
    Migration ponctuelle : l'ancien ENUM natif MySQL de sales.status avait des
    libellés en minuscules ('unpaid','paid','partial','credit','pending' — pas
    de 'cancelled' du tout). MySQL normalise toujours la valeur stockée sur la
    casse du libellé déclaré : les ventes historiques ont donc été enregistrées
    en minuscules, et les ventes annulées tronquées en chaîne vide (valeur ENUM
    invalide en mode non strict, faute de libellé 'cancelled').

    L'ENUM a depuis été élargi en majuscules (avec CANCELLED). Cette fonction
    aligne les données existantes, indépendamment de l'état d'Alembic — la
    migration acac0d9c1008 fait la même chose, mais un graphe Alembic cassé
    peut empêcher son exécution ; cette fonction s'exécute à chaque démarrage
    (idempotente, no-op dès que tout est déjà en majuscules) pour garantir la
    correction sans dépendre d'Alembic ni d'une intervention manuelle.
    """
    from sqlalchemy import text as _text, inspect as _inspect

    import api.database as _db_mod
    _eng = active_engine or _db_mod.engine
    _log.info("status-casing: démarrage de la vérification (dialect=%s)", _eng.dialect.name)

    try:
        inspector = _inspect(_eng)
        if "sales" not in inspector.get_table_names():
            _log.warning("status-casing: table 'sales' absente, vérification ignorée")
            return
    except Exception as exc:
        _log.warning("status-casing: impossible d'inspecter le schéma: %s", exc)
        return

    # MySQL compare les VARCHAR/ENUM de façon insensible à la casse par défaut
    # (collation *_ci) : "status <> UPPER(status)" y est TOUJOURS faux même
    # pour une ligne 'paid', donc aucune ligne n'est jamais sélectionnée sans
    # forcer une comparaison binaire. SQLite est déjà sensible à la casse par
    # défaut, BINARY n'y est pas nécessaire (et non supporté).
    is_mysql = _eng.dialect.name == "mysql"
    status_expr = "BINARY status" if is_mysql else "status"

    with _eng.connect() as conn:
        try:
            pending = conn.execute(_text(
                f"SELECT COUNT(*) FROM sales WHERE {status_expr} <> UPPER(status) OR status = ''"
            )).scalar()
        except Exception as exc:
            _log.warning("status-casing: vérification impossible: %s", exc)
            return

        if not pending:
            _log.info("status-casing: vérification OK, 0 ligne à corriger")
            return

        _log.info("status-casing: %d ligne(s) à corriger détectée(s), correction en cours…", pending)
        try:
            conn.execute(_text(
                f"UPDATE sales SET status = UPPER(status) WHERE {status_expr} <> UPPER(status)"
            ))
            conn.execute(_text(
                "UPDATE sales SET status = 'CANCELLED' WHERE status = ''"
            ))
            conn.commit()
            _log.info("status-casing: %d vente(s) normalisée(s) vers la casse majuscule", pending)
        except Exception as exc:
            conn.rollback()
            _log.warning("status-casing: échec de la normalisation: %s", exc)


def _repair_duplicate_registers(active_engine=None) -> None:
    """
    Migration ponctuelle : PosRegister déclare UniqueConstraint('tenant_id',
    'device_id', name='uq_register_tenant_device') dans le modèle, mais
    _sync_schema_from_models() n'ajoute que des COLONNES manquantes — jamais
    de contraintes/index — donc cette contrainte n'a jamais été réellement
    appliquée sur une table pos_registers déjà existante en production
    (seule une table créée à partir de zéro via create_all() l'obtient).
    Résultat : deux registres ont pu être créés pour le même (tenant_id,
    device_id) sur le cloud, et une installation locale fraîche (dont la
    table respecte la contrainte dès sa création) échoue à les tirer tous
    les deux ("Duplicate entry ... for key uq_register_tenant_device").

    Corrige en désactivant (is_active=False, non destructif) tous les
    doublons sauf le plus récemment vu par (tenant_id, device_id), puis tente
    d'ajouter la contrainte manquante (idempotente, MySQL uniquement — sans
    ça la prochaine duplication ne serait jamais empêchée). S'exécute à
    chaque démarrage.
    """
    from sqlalchemy import text as _text, inspect as _inspect

    import api.database as _db_mod
    _eng = active_engine or _db_mod.engine
    if _eng.dialect.name != "mysql":
        return

    try:
        inspector = _inspect(_eng)
        if "pos_registers" not in inspector.get_table_names():
            return
    except Exception as exc:
        _log.warning("registres dupliqués: impossible d'inspecter le schéma: %s", exc)
        return

    with _eng.connect() as conn:
        try:
            dupes = conn.execute(_text(
                "SELECT tenant_id, device_id, COUNT(*) AS n "
                "FROM pos_registers "
                "WHERE device_id IS NOT NULL "
                "GROUP BY tenant_id, device_id HAVING COUNT(*) > 1"
            )).fetchall()
        except Exception as exc:
            _log.warning("registres dupliqués: vérification impossible: %s", exc)
            return

        if dupes:
            _log.warning("registres dupliqués: %d paire(s) (tenant_id, device_id) en doublon détectée(s)", len(dupes))
            for tenant_id, device_id, _n in dupes:
                try:
                    rows = conn.execute(_text(
                        "SELECT id FROM pos_registers "
                        "WHERE tenant_id = :tid AND device_id = :did "
                        "ORDER BY last_seen IS NULL, last_seen DESC, updated_at DESC"
                    ), {"tid": tenant_id, "did": device_id}).fetchall()
                    keep_id = rows[0][0]
                    for (rid,) in rows[1:]:
                        conn.execute(_text(
                            "UPDATE pos_registers SET is_active = 0 WHERE id = :rid"
                        ), {"rid": rid})
                    conn.commit()
                    _log.warning(
                        "registres dupliqués: tenant=%s device=%s → conservé %s, désactivé %d autre(s)",
                        tenant_id, device_id, keep_id, len(rows) - 1,
                    )
                except Exception as exc:
                    conn.rollback()
                    _log.warning("registres dupliqués: correction tenant=%s device=%s: %s", tenant_id, device_id, exc)
        else:
            _log.info("registres dupliqués: vérification OK, 0 doublon à corriger")

        try:
            indexes = inspector.get_indexes("pos_registers")
            if not any(idx["name"] == "uq_register_tenant_device" for idx in indexes):
                conn.execute(_text(
                    "ALTER TABLE `pos_registers` "
                    "ADD UNIQUE KEY `uq_register_tenant_device` (`tenant_id`, `device_id`)"
                ))
                conn.commit()
                _log.info("registres dupliqués: contrainte uq_register_tenant_device ajoutée")
        except Exception as exc:
            conn.rollback()
            _log.warning("registres dupliqués: ajout de la contrainte échoué (nouveaux doublons ?): %s", exc)


def _repair_annual_discount_default(active_engine=None) -> None:
    """
    Migration ponctuelle : PlatformConfig.annual_discount_pct déclare
    default=20 côté Python, mais _sync_schema_from_models() ne générait
    jusqu'ici une clause DEFAULT que depuis server_default — un default=
    Python n'était jamais honoré lors de l'ADD COLUMN sur une table déjà
    existante, qui retombait alors sur le neutre "DEFAULT 0" (colonne
    entière NOT NULL). platform_config est une ligne unique : ce 0 s'est
    donc retrouvé affiché partout comme "Annuel -0%" au lieu de -20%.

    Corrige la ligne existante si elle est encore à 0 (jamais explicitement
    configurée) — n'écrase pas un choix admin ultérieur différent de 0.
    Idempotente, s'exécute à chaque démarrage.
    """
    from sqlalchemy import inspect as _inspect

    import api.database as _db_mod
    _eng = active_engine or _db_mod.engine

    try:
        inspector = _inspect(_eng)
        if "platform_config" not in inspector.get_table_names():
            return
    except Exception as exc:
        _log.warning("annual-discount: impossible d'inspecter le schéma: %s", exc)
        return

    with _eng.connect() as conn:
        try:
            row = conn.execute(text(
                "SELECT id, annual_discount_pct FROM platform_config LIMIT 1"
            )).first()
        except Exception as exc:
            _log.warning("annual-discount: vérification impossible: %s", exc)
            return

        if not row or row[1] != 0:
            _log.info("annual-discount: vérification OK, rien à corriger")
            return

        try:
            conn.execute(text(
                "UPDATE platform_config SET annual_discount_pct = 20 WHERE id = :id"
            ), {"id": row[0]})
            conn.commit()
            _log.warning("annual-discount: platform_config.annual_discount_pct corrigé 0 → 20")
        except Exception as exc:
            conn.rollback()
            _log.warning("annual-discount: échec de la correction: %s", exc)


def _backfill_stock_movement_warehouse(active_engine=None) -> None:
    """
    Migration ponctuelle : jusqu'ici, `Product.stock` additionnait TOUS les
    stock_movements du tenant sans filtrer par dépôt (stock effectivement
    global) — de nombreux mouvements historiques (ajustements manuels, entre
    autres) ont donc `warehouse_id = NULL`. Le stock devient maintenant
    réellement PAR DÉPÔT (une caisse ne vend que ce qui est tracé pour SON
    dépôt — voir Product.available_quantity_at / create_sale) : sans ce
    correctif, tout le stock historique d'un tenant multi-dépôts deviendrait
    invisible à la vente du jour au lendemain.

    Rattache les mouvements orphelins (warehouse_id NULL) au dépôt par défaut
    de leur tenant — préserve exactement le total actuel pour les tenants
    mono-dépôt (aucun changement visible) ; les tenants multi-dépôts devront
    ensuite utiliser Distribuer (Entrepôt) pour répartir correctement si la
    réalité diffère (aucun moyen fiable de deviner rétroactivement où se
    trouvait physiquement chaque mouvement). Les tenants sans AUCUN Warehouse
    (mono-dépôt local) ne sont pas concernés — create_sale se rabat alors sur
    le total global, donc aucune régression possible pour eux.

    Idempotente (ne touche que warehouse_id IS NULL), s'exécute à chaque
    démarrage.
    """
    from sqlalchemy import inspect as _inspect

    import api.database as _db_mod
    _eng = active_engine or _db_mod.engine

    try:
        inspector = _inspect(_eng)
        tables = inspector.get_table_names()
        if "stock_movements" not in tables or "warehouses" not in tables:
            return
    except Exception as exc:
        _log.warning("backfill-stock-warehouse: impossible d'inspecter le schéma: %s", exc)
        return

    with _eng.connect() as conn:
        try:
            default_warehouses = conn.execute(text(
                "SELECT tenant_id, id FROM warehouses WHERE is_default = 1 AND is_active = 1"
            )).fetchall()
        except Exception as exc:
            _log.warning("backfill-stock-warehouse: lecture des dépôts par défaut impossible: %s", exc)
            return

        for tenant_id, default_wh_id in default_warehouses:
            if not tenant_id:
                continue
            try:
                result = conn.execute(text(
                    "UPDATE stock_movements SET warehouse_id = :wh "
                    "WHERE warehouse_id IS NULL AND tenant_id = :tid"
                ), {"wh": default_wh_id, "tid": tenant_id})
                conn.commit()
                if result.rowcount:
                    _log.warning(
                        "backfill-stock-warehouse: tenant %s — %d mouvement(s) rattaché(s) au dépôt par défaut %s",
                        tenant_id, result.rowcount, default_wh_id,
                    )
            except Exception as exc:
                conn.rollback()
                _log.warning("backfill-stock-warehouse: échec pour le tenant %s: %s", tenant_id, exc)


def _repair_entrepot_is_claimed(active_engine=None) -> None:
    """
    Migration ponctuelle : avant ce correctif, l'entrepôt était créé avec
    is_claimed=False comme un dépôt normal — l'écran Dépôts (qui ne filtre
    pas is_entrepot) et GET /warehouses/{id}/install-code (qui génère un
    code à la volée pour tout dépôt non réclamé) l'affichaient donc comme un
    business installable, avec son propre code d'installation.

    Force is_claimed=1 pour tout warehouse is_entrepot=1 déjà créé, et
    supprime les InstallationCode déjà générés pour eux (sinon un code
    généré avant ce correctif resterait valide/rachetable).

    Idempotente, s'exécute à chaque démarrage.
    """
    from sqlalchemy import inspect as _inspect

    import api.database as _db_mod
    _eng = active_engine or _db_mod.engine

    try:
        inspector = _inspect(_eng)
        tables = inspector.get_table_names()
        if "warehouses" not in tables:
            return
    except Exception as exc:
        _log.warning("repair-entrepot-claimed: impossible d'inspecter le schéma: %s", exc)
        return

    with _eng.connect() as conn:
        try:
            if "installation_codes" in tables:
                conn.execute(text(
                    "DELETE FROM installation_codes WHERE warehouse_id IN "
                    "(SELECT id FROM warehouses WHERE is_entrepot = 1)"
                ))
            result = conn.execute(text(
                "UPDATE warehouses SET is_claimed = 1 "
                "WHERE is_entrepot = 1 AND is_claimed = 0"
            ))
            conn.commit()
            if result.rowcount:
                _log.warning(
                    "repair-entrepot-claimed: %d entrepôt(s) marqué(s) is_claimed=1",
                    result.rowcount,
                )
        except Exception as exc:
            conn.rollback()
            _log.warning("repair-entrepot-claimed: échec: %s", exc)


def _repair_cross_tenant_app_config(active_engine=None) -> None:
    """
    Migration ponctuelle : `config.py::_wh_id()` acceptait un warehouse_id
    fourni par le client (query param) sans vérifier qu'il appartenait bien au
    tenant de l'utilisateur authentifié (bug corrigé dans le même changement
    que cette fonction). Résultat possible : des lignes app_config créées avec
    un warehouse_id pointant vers le dépôt d'un AUTRE tenant — invisible côté
    cloud (la contrainte FK est satisfaite, la ligne référencée existe bien,
    juste sous le mauvais tenant), mais provoque une erreur de contrainte FK
    dès qu'une installation locale tire cette ligne (le dépôt étranger n'existe
    pas localement, car hors du tenant de cette installation).

    Corrige en réinitialisant warehouse_id à NULL (config globale du tenant —
    repli déjà géré par config_service.get_or_create). Idempotente, s'exécute
    à chaque démarrage.
    """
    from sqlalchemy import text as _text, inspect as _inspect

    import api.database as _db_mod
    _eng = active_engine or _db_mod.engine

    try:
        inspector = _inspect(_eng)
        tables = inspector.get_table_names()
        if "app_config" not in tables or "warehouses" not in tables:
            return
    except Exception as exc:
        _log.warning("app_config cross-tenant: impossible d'inspecter le schéma: %s", exc)
        return

    with _eng.connect() as conn:
        try:
            pending = conn.execute(_text(
                "SELECT COUNT(*) FROM app_config ac "
                "JOIN warehouses w ON ac.warehouse_id = w.id "
                "WHERE ac.tenant_id IS NOT NULL AND w.tenant_id IS NOT NULL "
                "AND ac.tenant_id <> w.tenant_id"
            )).scalar()
        except Exception as exc:
            _log.warning("app_config cross-tenant: vérification impossible: %s", exc)
            return

        if not pending:
            _log.info("app_config cross-tenant: vérification OK, 0 ligne à corriger")
            return

        _log.warning(
            "app_config cross-tenant: %d ligne(s) corrompue(s) détectée(s), correction en cours…",
            pending,
        )
        try:
            if _eng.dialect.name == "mysql":
                conn.execute(_text(
                    "UPDATE app_config ac "
                    "JOIN warehouses w ON ac.warehouse_id = w.id "
                    "SET ac.warehouse_id = NULL "
                    "WHERE ac.tenant_id IS NOT NULL AND w.tenant_id IS NOT NULL "
                    "AND ac.tenant_id <> w.tenant_id"
                ))
            else:
                conn.execute(_text(
                    "UPDATE app_config SET warehouse_id = NULL WHERE id IN ("
                    "SELECT ac.id FROM app_config ac "
                    "JOIN warehouses w ON ac.warehouse_id = w.id "
                    "WHERE ac.tenant_id IS NOT NULL AND w.tenant_id IS NOT NULL "
                    "AND ac.tenant_id <> w.tenant_id)"
                ))
            conn.commit()
            _log.warning(
                "app_config cross-tenant: %d ligne(s) corrigée(s) (warehouse_id réinitialisé à NULL)",
                pending,
            )
        except Exception as exc:
            conn.rollback()
            _log.warning("app_config cross-tenant: échec de la correction: %s", exc)


def _migrate_register_dates_to_shared_key(active_engine=None) -> None:
    """
    Migration ponctuelle : PosRegister.trial_ends_at / subscription_started_at /
    subscription_ends_at étaient chiffrées avec une clé dérivée de
    settings.SECRET_KEY — propre à CHAQUE serveur (cloud, chaque installation
    Windows). Comme pos_register se synchronise entre le cloud et les
    installations locales (SYNC_ENTITIES, direction "both"), un serveur ne
    pouvait jamais déchiffrer une date chiffrée par un AUTRE serveur : le
    déchiffrement échouait silencieusement et la date apparaissait comme
    absente (voir try_decrypt_register_date).

    Ces champs utilisent désormais une clé fixe partagée par tous les
    serveurs (_REGISTER_DATE_MASTER_KEY, billing_crypto.py). Cette fonction
    re-chiffre les données existantes créées AVANT ce changement : pour
    chaque caisse, tente un déchiffrement avec l'ancien schéma (clé =
    SECRET_KEY de CE serveur) ; en cas de succès (donnée créée localement,
    ici, sous l'ancien schéma), la valeur est ré-écrite via la propriété
    Python normale, qui la re-chiffre automatiquement avec la nouvelle clé
    fixe. Idempotente : sans effet sur des données déjà migrées ou reçues
    d'un autre serveur (jamais déchiffrables ici de toute façon, ancien
    schéma ou nouveau).
    """
    from sqlalchemy.orm import sessionmaker as _sessionmaker
    from api.core.billing_crypto import try_decrypt_register_date_legacy
    from api.models.PosRegister import PosRegister
    import api.database as _db_mod

    _eng = active_engine or _db_mod.engine
    db = _sessionmaker(bind=_eng)()
    try:
        migrated = 0
        for reg in db.query(PosRegister).all():
            changed = False
            for raw_attr in ("_trial_ends_at", "_subscription_started_at", "_subscription_ends_at"):
                raw_val = getattr(reg, raw_attr, None)
                if not raw_val:
                    continue
                plaintext = try_decrypt_register_date_legacy(raw_val, reg.id)
                if plaintext is not None:
                    setattr(reg, raw_attr[1:], plaintext)  # passe par le setter → re-chiffre (clé fixe)
                    changed = True
            if changed:
                migrated += 1
        if migrated:
            db.commit()
            _log.info("register-dates: %d caisse(s) migrée(s) vers la clé de chiffrement partagée", migrated)
    except Exception as exc:
        db.rollback()
        _log.warning("register-dates: échec de la migration: %s", exc)
    finally:
        db.close()


def _ensure_default_warehouse(db, tenant_id: str | None) -> None:
    """
    Les dépôts viennent UNIQUEMENT du cloud via sync pull.
    Cette fonction n'en crée jamais. Elle aligne seulement is_default
    sur le dépôt indiqué par INSTALLER_WAREHOUSE_ID s'il existe déjà en base.
    """
    if not tenant_id:
        return
    from api.models.Warehouse import Warehouse as WarehouseModel
    from api.core.config import settings as _cfg
    try:
        installer_wh_id = _cfg.INSTALLER_WAREHOUSE_ID or None
        if not installer_wh_id:
            return
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

        # Ces correctifs portent sur des tables déjà existantes et sont
        # indépendants de create_all() (qui ne fait que créer les tables
        # manquantes) — ils doivent tourner même si create_all() a échoué,
        # sans quoi un échec sans rapport avec sales.status bloquait aussi
        # silencieusement la correction de la casse de sales.status.
        try:
            _run_alembic_migrations()
        except Exception as exc:
            _log.warning("Alembic migration warning: %s", exc)
        # 2b. Synchronise automatiquement le schéma DB avec les modèles SQLAlchemy
        _sync_schema_from_models(_active_engine)
        # 2c. Corrige les colonnes DATETIME → TEXT(600) pour les dates Fernet de pos_registers
        _fix_register_billing_date_columns(_active_engine)
        # 2d. Convertit les unique globaux en unique par-tenant (MySQL uniquement)
        _migrate_per_tenant_unique(_active_engine)
        # 2e. Décale -5h les DateTime historiques (UTC → Haiti local, one-shot)
        _backfill_haiti_local_time(_active_engine)
        # 2f. Normalise la casse historique de sales.status (one-shot)
        _normalize_sale_status_casing(_active_engine)
        # 2g. Re-chiffre les dates de caisse vers la clé partagée (one-shot)
        _migrate_register_dates_to_shared_key(_active_engine)
        # 2h. Corrige les app_config avec un warehouse_id cross-tenant (one-shot)
        _repair_cross_tenant_app_config(_active_engine)
        # 2i. Désactive les pos_registers dupliqués (tenant_id, device_id) et
        # ajoute la contrainte manquante (one-shot, MySQL uniquement)
        _repair_duplicate_registers(_active_engine)
        # 2j. Corrige platform_config.annual_discount_pct si resté à 0 (one-shot)
        _repair_annual_discount_default(_active_engine)
        # 2k. Rattache les stock_movements orphelins (warehouse_id NULL) au
        # dépôt par défaut de leur tenant — le stock devient réellement par
        # dépôt (one-shot, voir docstring de la fonction)
        _backfill_stock_movement_warehouse(_active_engine)
        # 2l. Marque les entrepôts déjà créés comme is_claimed=1 et supprime
        # leurs codes d'installation existants — l'entrepôt n'est pas un
        # poste de vente installable (one-shot, voir docstring de la fonction)
        _repair_entrepot_is_claimed(_active_engine)
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

_MDNS_WATCH_INTERVAL = 120  # secondes entre deux vérifications de l'IP locale
_mdns_watch_task: asyncio.Task | None = None


async def _mdns_watch_loop():
    """Revérifie périodiquement l'IP locale et redémarre la diffusion mDNS
    si elle a changé (bail DHCP renouvelé, routeur redémarré...) — sans
    ceci, infini-post.local resterait figé sur une IP périmée jusqu'au
    prochain redémarrage du service (voir mdns_service.refresh_if_ip_changed)."""
    from api.services.mdns_service import refresh_if_ip_changed
    while True:
        await asyncio.sleep(_MDNS_WATCH_INTERVAL)
        try:
            refresh_if_ip_changed()
        except Exception:
            logging.getLogger("pos.mdns").exception("Échec vérification IP mDNS")


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

    # mDNS ("infini-post.local") — installation locale Windows uniquement.
    # Le cloud (Docker/Linux) n'a pas de réseau local a annoncer.
    if os.name == "nt":
        global _mdns_watch_task
        from api.services.mdns_service import start_mdns_responder
        start_mdns_responder()
        _mdns_watch_task = asyncio.create_task(_mdns_watch_loop())


@app.on_event("shutdown")
async def stop_mdns():
    if os.name == "nt":
        if _mdns_watch_task and not _mdns_watch_task.done():
            _mdns_watch_task.cancel()
        from api.services.mdns_service import stop_mdns_responder
        stop_mdns_responder()


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

    # Fallback SPA (nécessaire pour usePathUrlStrategy() côté Flutter web —
    # URLs sans # : voir frontend/lib/main.dart) : toute route qui ne
    # correspond ni à l'API (déjà enregistrée plus haut, donc prioritaire)
    # ni à un fichier statique existant reçoit index.html, exactement comme
    # le "try_files ... /index.html" de nginx côté cloud
    # (pos.infini-software.cloud.nginx.conf, déjà en place). Ce serveur
    # local n'a pas de nginx devant lui — FastAPI doit jouer ce rôle
    # lui-même, remplace donc le simple StaticFiles(html=True) (qui ne
    # gérait que "/", pas les sous-routes profondes type /dashboard).
    _web_dir_resolved = _web_dir.resolve()

    @app.get("/{full_path:path}", include_in_schema=False)
    async def _serve_spa(full_path: str):
        candidate = (_web_dir_resolved / full_path).resolve()
        try:
            candidate.relative_to(_web_dir_resolved)
        except ValueError:
            # Tentative de sortir de _web_dir (ex: "../../etc/passwd") — refuse.
            candidate = _web_dir_resolved / "index.html"
        if not candidate.is_file():
            candidate = _web_dir_resolved / "index.html"
        headers = _NO_CACHE if candidate.name == "index.html" else None
        return FileResponse(str(candidate), headers=headers)

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
