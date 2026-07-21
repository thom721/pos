"""audit_lot_expiry — table audit_logs, lot/expiry sur stock_movements et purchase_receipt_items

Revision ID: a2b1c4d3e6f5
Revises: e1f2a3b4c5d6
Create Date: 2026-07-15 10:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'a2b1c4d3e6f5'
down_revision: Union[str, None] = 'e1f2a3b4c5d6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def _table_exists(table: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.TABLES "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t"
    ), {"t": table}).scalar()
    return bool(n)


def upgrade() -> None:
    if not _table_exists('audit_logs'):
        op.create_table(
            'audit_logs',
            sa.Column('id',            sa.String(36),  primary_key=True),
            sa.Column('tenant_id',     sa.String(36),  sa.ForeignKey('tenants.id'), nullable=True),
            sa.Column('user_id',       sa.String(36),  sa.ForeignKey('users.id'),   nullable=True),
            sa.Column('action',        sa.String(50),  nullable=False),
            sa.Column('resource_type', sa.String(50),  nullable=False),
            sa.Column('resource_id',   sa.String(100), nullable=True),
            sa.Column('detail',        sa.Text,        nullable=True),
            sa.Column('ip_address',    sa.String(45),  nullable=True),
            sa.Column('created_at',    sa.DateTime(timezone=True), nullable=False),
            sa.Column('updated_at',    sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index('idx_audit_tenant_created', 'audit_logs', ['tenant_id', 'created_at'])
        op.create_index('idx_audit_resource',       'audit_logs', ['resource_type', 'resource_id'])

    if not _col_exists('stock_movements', 'lot_number'):
        op.add_column('stock_movements',
            sa.Column('lot_number',  sa.String(100), nullable=True))
    if not _col_exists('stock_movements', 'expiry_date'):
        op.add_column('stock_movements',
            sa.Column('expiry_date', sa.Date, nullable=True))

    if not _col_exists('purchase_receipt_items', 'lot_number'):
        op.add_column('purchase_receipt_items',
            sa.Column('lot_number',  sa.String(100), nullable=True))
    if not _col_exists('purchase_receipt_items', 'expiry_date'):
        op.add_column('purchase_receipt_items',
            sa.Column('expiry_date', sa.Date, nullable=True))


def downgrade() -> None:
    op.drop_column('purchase_receipt_items', 'expiry_date')
    op.drop_column('purchase_receipt_items', 'lot_number')
    op.drop_column('stock_movements', 'expiry_date')
    op.drop_column('stock_movements', 'lot_number')
    op.drop_index('idx_audit_resource',       table_name='audit_logs')
    op.drop_index('idx_audit_tenant_created', table_name='audit_logs')
    op.drop_table('audit_logs')
