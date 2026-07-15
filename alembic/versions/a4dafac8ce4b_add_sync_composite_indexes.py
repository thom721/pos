"""add_sync_composite_indexes

Revision ID: a4dafac8ce4b
Revises: ca853a4cc1f8
Create Date: 2026-07-15 13:59:29.474079

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a4dafac8ce4b'
down_revision: Union[str, Sequence[str], None] = 'ca853a4cc1f8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# Tables with both tenant_id and updated_at — composite index covers pull queries.
_SYNC_TABLES_COMPOSITE = [
    "categories",
    "suppliers",
    "products",
    "customers",
    "users",
    "pos_registers",
    "sales",
    "sale_items",
    "payments",
    "return_records",
    "purchases",
    "purchase_items",
    "purchase_receipts",
    "purchase_receipt_items",
    "stock_movements",
    "inventory_records",
    "invoices",
    "proformas",
    "debts",
    "cashier_sessions",
    "audit_logs",
    "employee_profiles",
    "payroll_periods",
    "payroll_entries",
    "employee_loans",
    "payroll_loan_deductions",
]

# Child tables without tenant_id — single updated_at index covers pull queries.
_SYNC_TABLES_UPDATED_AT_ONLY = [
    "invoice_items",
    "proforma_items",
]


def upgrade() -> None:
    for table in _SYNC_TABLES_COMPOSITE:
        op.create_index(
            f"idx_{table}_tid_upd",
            table,
            ["tenant_id", "updated_at"],
            unique=False,
        )
    for table in _SYNC_TABLES_UPDATED_AT_ONLY:
        op.create_index(
            f"idx_{table}_upd",
            table,
            ["updated_at"],
            unique=False,
        )


def downgrade() -> None:
    for table in _SYNC_TABLES_COMPOSITE:
        op.drop_index(f"idx_{table}_tid_upd", table_name=table)
    for table in _SYNC_TABLES_UPDATED_AT_ONLY:
        op.drop_index(f"idx_{table}_upd", table_name=table)
