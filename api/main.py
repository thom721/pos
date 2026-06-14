
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

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/static", StaticFiles(directory="api/static"), name="static")

app.include_router(user.router)
app.include_router(login.router)
app.include_router(auth.router)
app.include_router(category.router)
app.include_router(supplier.router)
app.include_router(product.router)
app.include_router(purchases.router)
app.include_router(purchases_receive.router)
app.include_router(customer.router)
app.include_router(sales.router)
app.include_router(stock.router)
app.include_router(returns.router, prefix="/returns", tags=["Returns"])
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
    """
    from api.models.Tenant import Tenant as TenantModel

    local = db.query(TenantModel).filter(TenantModel.slug == "__local__").first()
    if not local:
        local = TenantModel(
            slug="__local__",
            business_name="Local",
            owner_email="local@localhost",
            status="local",
            is_local=True,
        )
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
        _ensure_local_tenant(db)
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
    finally:
        db.close()

@app.get("/health", include_in_schema=False)
async def health_root():
    return {"status": "ok"}

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
