from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context

# Import all models so Alembic autogenerate can detect them
from api.models import (  # noqa: F401
    Tenant, PosRegister, CashierSession, OfflineSyncQueue,
    User, Category, Supplier, Product, Customer, Sale, SaleItem,
    Purchase, PurchaseItem, PurchaseReceipt, PurchaseReceiptItem,
    Payment, StockMovement, Debt, ReturnRecord, InventoryRecord,
    AppConfig, Proforma, Invoice, EmployeeProfile, EmployeeLoan,
    PayrollPeriod, PayrollEntry, PayrollLoanDeduction, Role,
)
from api.database import Base, SQLALCHEMY_DATABASE_URL

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=SQLALCHEMY_DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    alembic_cfg = config.get_section(config.config_ini_section) or {}
    alembic_cfg["sqlalchemy.url"] = SQLALCHEMY_DATABASE_URL
    connectable = engine_from_config(
        alembic_cfg,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
