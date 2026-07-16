"""warehouse_id sur sales, cashier_sessions, return_records

Revision ID: k6l7m8n9o0p1
Revises: j5k6l7m8n9o0
Create Date: 2026-07-16
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'k6l7m8n9o0p1'
down_revision: Union[str, None] = 'j5k6l7m8n9o0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
    # ── sales ─────────────────────────────────────────────────────────────────
    if not _col_exists('sales', 'warehouse_id'):
        op.add_column('sales',
            sa.Column('warehouse_id', sa.String(36), nullable=True))
        op.create_foreign_key(
            'fk_sale_warehouse', 'sales', 'warehouses',
            ['warehouse_id'], ['id'])
        op.create_index('ix_sale_warehouse_id', 'sales', ['warehouse_id'])

    # ── cashier_sessions ──────────────────────────────────────────────────────
    if not _col_exists('cashier_sessions', 'warehouse_id'):
        op.add_column('cashier_sessions',
            sa.Column('warehouse_id', sa.String(36), nullable=True))
        op.create_foreign_key(
            'fk_session_warehouse', 'cashier_sessions', 'warehouses',
            ['warehouse_id'], ['id'])
        op.create_index('ix_session_warehouse_id', 'cashier_sessions', ['warehouse_id'])

    # ── return_records ────────────────────────────────────────────────────────
    if not _col_exists('return_records', 'warehouse_id'):
        op.add_column('return_records',
            sa.Column('warehouse_id', sa.String(36), nullable=True))
        op.create_foreign_key(
            'fk_return_warehouse', 'return_records', 'warehouses',
            ['warehouse_id'], ['id'])
        op.create_index('ix_return_warehouse_id', 'return_records', ['warehouse_id'])


def downgrade() -> None:
    op.drop_index('ix_return_warehouse_id',   table_name='return_records')
    op.drop_constraint('fk_return_warehouse', 'return_records',   type_='foreignkey')
    op.drop_column('return_records',   'warehouse_id')

    op.drop_index('ix_session_warehouse_id',   table_name='cashier_sessions')
    op.drop_constraint('fk_session_warehouse', 'cashier_sessions', type_='foreignkey')
    op.drop_column('cashier_sessions', 'warehouse_id')

    op.drop_index('ix_sale_warehouse_id',   table_name='sales')
    op.drop_constraint('fk_sale_warehouse', 'sales',              type_='foreignkey')
    op.drop_column('sales',            'warehouse_id')
