"""add_warehouses -- table warehouses + warehouse_id nullable sur 5 tables

Revision ID: i4j5k6l7m8n9
Revises: h3i4j5k6l7m8
Create Date: 2026-07-16
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'i4j5k6l7m8n9'
down_revision: Union[str, None] = 'h3i4j5k6l7m8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _table_exists(table: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.TABLES "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t"
    ), {"t": table}).scalar()
    return bool(n)


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
    # ── 1. Table warehouses ───────────────────────────────────────────────────
    if not _table_exists('warehouses'):
        op.create_table(
            'warehouses',
            sa.Column('id',          sa.String(36),  nullable=False),
            sa.Column('created_at',  sa.DateTime(),  nullable=True),
            sa.Column('updated_at',  sa.DateTime(),  nullable=True),
            sa.Column('tenant_id',   sa.String(36),  nullable=True),
            sa.Column('name',        sa.String(200),  nullable=False),
            sa.Column('description', sa.Text(),       nullable=True),
            sa.Column('is_active',   sa.Boolean(),    nullable=False, server_default='1'),
            sa.Column('is_default',  sa.Boolean(),    nullable=False, server_default='0'),
            sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_warehouses_tenant_id', 'warehouses', ['tenant_id'])

    # ── 2. stock_movements.warehouse_id ───────────────────────────────────────
    if not _col_exists('stock_movements', 'warehouse_id'):
        op.add_column('stock_movements',
            sa.Column('warehouse_id', sa.String(36), nullable=True))
        op.create_foreign_key(
            'fk_sm_warehouse', 'stock_movements', 'warehouses',
            ['warehouse_id'], ['id'])
        op.create_index('ix_sm_warehouse_id', 'stock_movements', ['warehouse_id'])

    # ── 3. purchases.warehouse_id ─────────────────────────────────────────────
    if not _col_exists('purchases', 'warehouse_id'):
        op.add_column('purchases',
            sa.Column('warehouse_id', sa.String(36), nullable=True))
        op.create_foreign_key(
            'fk_purchase_warehouse', 'purchases', 'warehouses',
            ['warehouse_id'], ['id'])
        op.create_index('ix_purchase_warehouse_id', 'purchases', ['warehouse_id'])

    # ── 4. purchase_receipts.warehouse_id ────────────────────────────────────
    if not _col_exists('purchase_receipts', 'warehouse_id'):
        op.add_column('purchase_receipts',
            sa.Column('warehouse_id', sa.String(36), nullable=True))
        op.create_foreign_key(
            'fk_pr_warehouse', 'purchase_receipts', 'warehouses',
            ['warehouse_id'], ['id'])
        op.create_index('ix_pr_warehouse_id', 'purchase_receipts', ['warehouse_id'])

    # ── 5. inventory_records.warehouse_id ────────────────────────────────────
    if not _col_exists('inventory_records', 'warehouse_id'):
        op.add_column('inventory_records',
            sa.Column('warehouse_id', sa.String(36), nullable=True))
        op.create_foreign_key(
            'fk_inv_warehouse', 'inventory_records', 'warehouses',
            ['warehouse_id'], ['id'])
        op.create_index('ix_inv_warehouse_id', 'inventory_records', ['warehouse_id'])

    # ── 6. pos_registers.warehouse_id ────────────────────────────────────────
    if not _col_exists('pos_registers', 'warehouse_id'):
        op.add_column('pos_registers',
            sa.Column('warehouse_id', sa.String(36), nullable=True))
        op.create_foreign_key(
            'fk_posreg_warehouse', 'pos_registers', 'warehouses',
            ['warehouse_id'], ['id'])
        op.create_index('ix_posreg_warehouse_id', 'pos_registers', ['warehouse_id'])


def downgrade() -> None:
    op.drop_index('ix_posreg_warehouse_id',  table_name='pos_registers')
    op.drop_constraint('fk_posreg_warehouse', 'pos_registers',   type_='foreignkey')
    op.drop_column('pos_registers', 'warehouse_id')

    op.drop_index('ix_inv_warehouse_id',     table_name='inventory_records')
    op.drop_constraint('fk_inv_warehouse',   'inventory_records', type_='foreignkey')
    op.drop_column('inventory_records', 'warehouse_id')

    op.drop_index('ix_pr_warehouse_id',      table_name='purchase_receipts')
    op.drop_constraint('fk_pr_warehouse',    'purchase_receipts', type_='foreignkey')
    op.drop_column('purchase_receipts', 'warehouse_id')

    op.drop_index('ix_purchase_warehouse_id', table_name='purchases')
    op.drop_constraint('fk_purchase_warehouse', 'purchases',      type_='foreignkey')
    op.drop_column('purchases', 'warehouse_id')

    op.drop_index('ix_sm_warehouse_id',      table_name='stock_movements')
    op.drop_constraint('fk_sm_warehouse',    'stock_movements',   type_='foreignkey')
    op.drop_column('stock_movements', 'warehouse_id')

    op.drop_index('ix_warehouses_tenant_id', table_name='warehouses')
    op.drop_table('warehouses')
