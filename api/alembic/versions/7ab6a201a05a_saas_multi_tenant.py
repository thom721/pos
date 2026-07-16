"""saas_multi_tenant

Revision ID: 7ab6a201a05a
Revises: 2c53e0439622
Create Date: 2026-06-14 14:05:16.311814

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7ab6a201a05a'
down_revision: Union[str, Sequence[str], None] = '2c53e0439622'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Tables qui reçoivent toutes la même colonne tenant_id + index + FK
_TABLES = [
    'app_config', 'categories', 'customers', 'debts', 'employee_loans',
    'employee_profiles', 'inventory_records', 'invoices', 'payments',
    'payroll_entries', 'payroll_loan_deductions', 'payroll_periods',
    'products', 'proformas', 'purchase_items', 'purchase_receipt_items',
    'purchase_receipts', 'purchases', 'return_records', 'roles',
    'sale_items', 'sales', 'stock_movements', 'suppliers', 'users',
]


def _col_exists(table: str) -> bool:
    """True si tenant_id existe déjà (migration partiellement appliquée)."""
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() "
        "AND TABLE_NAME = :t AND COLUMN_NAME = 'tenant_id'"
    ), {"t": table}).scalar()
    return bool(n)


def upgrade() -> None:
    """Upgrade schema — idempotente : saute les colonnes déjà présentes."""
    for table in _TABLES:
        if _col_exists(table):
            continue
        op.add_column(table, sa.Column('tenant_id', sa.String(length=36), nullable=True))
        op.create_index(op.f(f'ix_{table}_tenant_id'), table, ['tenant_id'], unique=False)
        op.create_foreign_key(None, table, 'tenants', ['tenant_id'], ['id'])


def downgrade() -> None:
    """Downgrade schema."""
    for table in reversed(_TABLES):
        op.drop_constraint(None, table, type_='foreignkey')
        op.drop_index(op.f(f'ix_{table}_tenant_id'), table_name=table)
        op.drop_column(table, 'tenant_id')
