
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
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
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
# Import models so create_all picks them up
from api.models import (  # noqa: F401
    Tenant, PosRegister, CashierSession, OfflineSyncQueue,
    BillingPayment, Proforma, Invoice, InventoryRecord, Role,
    PlatformConfig, SyncState,
)
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
app.include_router(admin_router.router)

# ── Built-in role definitions ─────────────────────────────────────────────────
_BUILTIN_ROLES = [
    {"name": "admin",         "label": "Administrateur", "color": "#7C3AED", "permissions": ["all"]},
    {"name": "manager",       "label": "Gérant",          "color": "#0284C7", "permissions": None},
    {"name": "cashier",       "label": "Caissier",         "color": "#059669", "permissions": None},
    {"name": "stock_manager", "label": "Resp. Stock",      "color": "#D97706", "permissions": None},
]


def _run_alembic_migrations() -> None:
    """
    Applique les migrations Alembic en attente.

    Nouveau déploiement (aucune table) :
      → create_all crée toutes les tables, puis on stamp 'head'
        pour qu'Alembic sache que la baseline est déjà en place.

    Déploiement existant (tables déjà là) :
      → alembic upgrade head applique uniquement les nouvelles migrations.
    """
    import os
    from alembic.config import Config as AlembicConfig
    from alembic import command as alembic_command

    ini_path = os.path.join(os.path.dirname(__file__), "alembic.ini")
    alembic_cfg = AlembicConfig(ini_path)

    with engine.connect() as conn:
        has_alembic_table = engine.dialect.has_table(conn, "alembic_version")
        if not has_alembic_table:
            # Nouveau déploiement : les tables viennent d'être créées par create_all.
            # On marque directement la baseline pour éviter de ré-exécuter upgrade.
            _log.info("Nouveau déploiement — stamp Alembic à 'head'")
            alembic_command.stamp(alembic_cfg, "head")
        else:
            _log.info("Déploiement existant — alembic upgrade head")
            alembic_command.upgrade(alembic_cfg, "head")


def _ensure_local_tenant(db) -> str:
    """
    In local-mode deployments, create a sentinel LOCAL tenant (once)
    and backfill all existing rows that have tenant_id = NULL.
    Returns the LOCAL tenant id.

    If the server was linked to a cloud tenant via connect_tenant, the INI
    contains cloud_tenant_id — the local tenant will have that same UUID so
    that pulled records (which carry the cloud tenant_id) are always valid
    without any substitution.
    """
    from api.models.Tenant import Tenant as TenantModel
    from api.core.config import load_ini_config

    ini = load_ini_config()
    cloud_tid = (ini.get("CLOUD_TENANT_ID") or ini.get("cloud_tenant_id") or "").strip()

    local = None
    if cloud_tid:
        local = db.query(TenantModel).filter(TenantModel.id == cloud_tid).first()
    if not local:
        local = db.query(TenantModel).filter(TenantModel.slug == "__local__").first()

    if not local:
        kwargs = dict(
            slug="__local__",
            business_name="Local",
            owner_email="local@localhost",
            status="local",
            is_local=True,
        )
        if cloud_tid:
            kwargs["id"] = cloud_tid
        local = TenantModel(**kwargs)
        db.add(local)
        db.flush()
        _log.info("Tenant LOCAL créé : %s", local.id)

    tid = local.id

    # Tables that now carry tenant_id — backfill NULLs once
    _TENANT_TABLES = [
        "users", "categories", "suppliers", "products", "customers",
        "sales", "sale_items", "purchases", "purchase_items",
        "purchase_receipts", "purchase_receipt_items",
        "payments", "stock_movements", "debts", "return_records",
        "inventory_records", "app_config", "proformas", "proforma_items",
        "invoices", "invoice_items", "employee_profiles", "employee_loans",
        "payroll_periods", "payroll_entries", "payroll_loan_deductions", "roles",
    ]
    for tbl in _TENANT_TABLES:
        try:
            db.execute(
                text(f"UPDATE `{tbl}` SET tenant_id = :tid WHERE tenant_id IS NULL"),
                {"tid": tid},
            )
        except Exception:
            pass  # table might not exist yet on first boot

    db.commit()
    return tid


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

    # Si les credentials existaient déjà mais pas l'user → générer un nouveau mdp
    if not raw_password:
        raw_password = secrets.token_urlsafe(12)
        admin_hash   = get_password_hash(raw_password)
        cfg.admin_password_hash      = admin_hash
        settings.ADMIN_PASSWORD_HASH = admin_hash
        db.commit()
        _log.info("=" * 62)
        _log.info("  UTILISATEUR ADMIN RECRÉÉ — NOUVEAU MOT DE PASSE")
        _log.info("  Email    : %s", admin_email)
        _log.info("  Password : %s", raw_password)
        _log.info("  → Changez ce mot de passe via le panel /admin")
        _log.info("=" * 62)

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


@app.on_event("startup")
def on_startup():
    from api.database import SessionLocal
    from api.models.Role import Role as RoleModel
    from api.core.permissions import ROLE_PERMISSIONS, load_roles_from_db

    # 1. Crée les tables manquantes (nouveau déploiement ou nouvelle table ajoutée)
    Base.metadata.create_all(bind=engine)
    # 2. Applique les migrations Alembic (ou stamp si premier démarrage)
    try:
        _run_alembic_migrations()
    except Exception as exc:
        _log.warning("Alembic migration warning: %s", exc)

    db = SessionLocal()
    try:
        # 3. Tenant LOCAL — pour les déploiements en mode local (pas SaaS)
        local_tid = _ensure_local_tenant(db)
        # 4. Superadmin — auto-génère les credentials si absent, crée le user
        _ensure_cloud_admin(db, local_tid)
        # Seed built-in roles if not present
        for rd in _BUILTIN_ROLES:
            existing = db.query(RoleModel).filter(RoleModel.name == rd["name"]).first()
            if not existing:
                perms = rd["permissions"] if rd["permissions"] is not None \
                    else list(ROLE_PERMISSIONS.get(rd["name"], set()))
                db.add(RoleModel(
                    name=rd["name"],
                    label=rd["label"],
                    color=rd["color"],
                    is_builtin=True,
                    permissions=perms,
                ))
        db.commit()

        # Load all roles (including custom ones) into ROLE_PERMISSIONS
        load_roles_from_db(db.query(RoleModel).all())

        # Inline migration: make users.phone nullable (safe on MySQL & SQLite)
        try:
            from api.core.config import settings as _s
            if _s.DB_TYPE != "sqlite":
                db.execute(text(
                    "ALTER TABLE users MODIFY COLUMN phone VARCHAR(255) NULL"
                ))
                db.commit()
        except Exception:
            pass  # already nullable or SQLite (no ALTER TABLE MODIFY)
    finally:
        db.close()

_AUTO_SYNC_INTERVAL = 300  # secondes entre chaque cycle (5 min)
_auto_sync_task: asyncio.Task | None = None


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
    """Background loop: sync toutes les 5 min si cloud_sync_enabled=True."""
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
                _slog.info("Auto-sync OK — pushed=%d pulled=%d", pushed_total, pulled_total)
            else:
                _slog.warning("Auto-sync partial — errors: %s", result.get("errors"))
        except Exception as exc:
            logging.getLogger("pos.autosync").error("Auto-sync loop error: %s", exc)
        await asyncio.sleep(_AUTO_SYNC_INTERVAL)


@app.on_event("startup")
async def start_auto_sync():
    global _auto_sync_task
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
