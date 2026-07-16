"""tenant_selfhosted_and_caisses

Revision ID: e1f2a3b4c5d6
Revises: d7e8f9a0b1c2
Create Date: 2026-06-16 12:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'e1f2a3b4c5d6'
down_revision: Union[str, None] = 'd7e8f9a0b1c2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
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
    if not _col_exists('platform_config', 'price_per_extra_caisse_htg'):
        op.add_column('platform_config',
            sa.Column('price_per_extra_caisse_htg', sa.Numeric(10, 2),
                      nullable=False, server_default='500.00'))
    if not _col_exists('platform_config', 'price_per_extra_caisse_usd'):
        op.add_column('platform_config',
            sa.Column('price_per_extra_caisse_usd', sa.Numeric(10, 2),
                      nullable=False, server_default='4.00'))


def downgrade() -> None:
    op.drop_column('platform_config', 'price_per_extra_caisse_usd')
    op.drop_column('platform_config', 'price_per_extra_caisse_htg')
    op.drop_column('tenants', 'can_manage_tenants')
    op.drop_column('tenants', 'max_caisses')
    op.drop_column('tenants', 'self_hosted_url')
    op.drop_column('tenants', 'type')
