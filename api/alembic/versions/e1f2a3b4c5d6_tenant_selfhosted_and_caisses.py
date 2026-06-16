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


def upgrade() -> None:
    # Tenant — mode hébergement + caisses
    op.add_column('tenants',
        sa.Column('type', sa.String(20), nullable=False, server_default='shared'))
    op.add_column('tenants',
        sa.Column('self_hosted_url', sa.String(500), nullable=True))
    op.add_column('tenants',
        sa.Column('max_caisses', sa.Integer(), nullable=False, server_default='1'))
    op.add_column('tenants',
        sa.Column('can_manage_tenants', sa.Boolean(), nullable=False, server_default='0'))

    # PlatformConfig — prix par caisse supplémentaire
    op.add_column('platform_config',
        sa.Column('price_per_extra_caisse_htg', sa.Numeric(10, 2),
                  nullable=False, server_default='500.00'))
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
