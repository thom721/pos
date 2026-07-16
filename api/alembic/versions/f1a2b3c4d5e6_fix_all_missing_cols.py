"""fix_all_missing_cols — ajoute toutes les colonnes manquantes (idempotent)

Revision ID: f1a2b3c4d5e6
Revises: a1b2c3d4e5f6
Create Date: 2026-07-16 12:00:00.000000

Colonnes présentes dans les modèles ORM mais absentes de la DB de production
parce que :
  - ajoutées au modèle sans migration correspondante (tenants billing/stripe)
  - migrations précédentes stampées manuellement sans être exécutées
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'f1a2b3c4d5e6'
down_revision: Union[str, None] = 'a1b2c3d4e5f6'
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
    # ── tenants : colonnes billing / stripe / subscription ─────────────────────
    if not _col_exists('tenants', 'trial_ends_at'):
        op.add_column('tenants',
            sa.Column('trial_ends_at', sa.DateTime(timezone=True), nullable=True))
    if not _col_exists('tenants', 'subscription_started_at'):
        op.add_column('tenants',
            sa.Column('subscription_started_at', sa.DateTime(timezone=True), nullable=True))
    if not _col_exists('tenants', 'is_local'):
        op.add_column('tenants',
            sa.Column('is_local', sa.Boolean(), nullable=False, server_default='0'))
    if not _col_exists('tenants', 'stripe_customer_id'):
        op.add_column('tenants',
            sa.Column('stripe_customer_id', sa.String(100), nullable=True))
    if not _col_exists('tenants', 'stripe_subscription_id'):
        op.add_column('tenants',
            sa.Column('stripe_subscription_id', sa.String(100), nullable=True))
    if not _col_exists('tenants', 'subscription_ends_at'):
        op.add_column('tenants',
            sa.Column('subscription_ends_at', sa.DateTime(timezone=True), nullable=True))

    # ── tenants : colonnes self-hosted / caisses (migration e1f2a3b4c5d6) ──────
    if not _col_exists('tenants', 'type'):
        op.add_column('tenants',
            sa.Column('type', sa.String(20), nullable=False, server_default='shared'))
    if not _col_exists('tenants', 'self_hosted_url'):
        op.add_column('tenants',
            sa.Column('self_hosted_url', sa.String(500), nullable=True))
    if not _col_exists('tenants', 'max_caisses'):
        op.add_column('tenants',
            sa.Column('max_caisses', sa.Integer(), nullable=False, server_default='1'))
    if not _col_exists('tenants', 'can_manage_tenants'):
        op.add_column('tenants',
            sa.Column('can_manage_tenants', sa.Boolean(), nullable=False, server_default='0'))

    # ── platform_config : admin credentials (migration d7e8f9a0b1c2) ───────────
    if not _col_exists('platform_config', 'admin_email'):
        op.add_column('platform_config',
            sa.Column('admin_email', sa.String(200), nullable=False, server_default=''))
    if not _col_exists('platform_config', 'admin_password_hash'):
        op.add_column('platform_config',
            sa.Column('admin_password_hash', sa.String(255), nullable=False, server_default=''))

    # ── platform_config : prix par caisse (migration e1f2a3b4c5d6) ─────────────
    if not _col_exists('platform_config', 'price_per_extra_caisse_htg'):
        op.add_column('platform_config',
            sa.Column('price_per_extra_caisse_htg', sa.Numeric(10, 2),
                      nullable=False, server_default='500.00'))
    if not _col_exists('platform_config', 'price_per_extra_caisse_usd'):
        op.add_column('platform_config',
            sa.Column('price_per_extra_caisse_usd', sa.Numeric(10, 2),
                      nullable=False, server_default='4.00'))

    # ── audit_logs : table (migration a1b2c3d4e5f6) ───────────────────────────
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

    # ── stock_movements : lot / expiry (migration a1b2c3d4e5f6) ──────────────
    if not _col_exists('stock_movements', 'lot_number'):
        op.add_column('stock_movements',
            sa.Column('lot_number', sa.String(100), nullable=True))
    if not _col_exists('stock_movements', 'expiry_date'):
        op.add_column('stock_movements',
            sa.Column('expiry_date', sa.Date, nullable=True))

    # ── purchase_receipt_items : lot / expiry (migration a1b2c3d4e5f6) ────────
    if not _col_exists('purchase_receipt_items', 'lot_number'):
        op.add_column('purchase_receipt_items',
            sa.Column('lot_number', sa.String(100), nullable=True))
    if not _col_exists('purchase_receipt_items', 'expiry_date'):
        op.add_column('purchase_receipt_items',
            sa.Column('expiry_date', sa.Date, nullable=True))


def downgrade() -> None:
    op.drop_column('purchase_receipt_items', 'expiry_date')
    op.drop_column('purchase_receipt_items', 'lot_number')
    op.drop_column('stock_movements', 'expiry_date')
    op.drop_column('stock_movements', 'lot_number')
    try:
        op.drop_index('idx_audit_resource',       table_name='audit_logs')
        op.drop_index('idx_audit_tenant_created', table_name='audit_logs')
        op.drop_table('audit_logs')
    except Exception:
        pass
    op.drop_column('platform_config', 'price_per_extra_caisse_usd')
    op.drop_column('platform_config', 'price_per_extra_caisse_htg')
    op.drop_column('platform_config', 'admin_password_hash')
    op.drop_column('platform_config', 'admin_email')
    op.drop_column('tenants', 'can_manage_tenants')
    op.drop_column('tenants', 'max_caisses')
    op.drop_column('tenants', 'self_hosted_url')
    op.drop_column('tenants', 'type')
    op.drop_column('tenants', 'subscription_ends_at')
    op.drop_column('tenants', 'stripe_subscription_id')
    op.drop_column('tenants', 'stripe_customer_id')
    op.drop_column('tenants', 'is_local')
    op.drop_column('tenants', 'subscription_started_at')
    op.drop_column('tenants', 'trial_ends_at')
