"""add stat columns to platform_config

Revision ID: i9j0k1l2m3n4
Revises: h8i9j0k1l2m3
Down_revision: h8i9j0k1l2m3
Branch_labels: None
Depends_on: None
"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    op.add_column('platform_config',
        sa.Column('stat_businesses',       sa.String(30), nullable=False, server_default='500+'))
    op.add_column('platform_config',
        sa.Column('stat_transactions_day', sa.String(30), nullable=False, server_default='10k+'))
    op.add_column('platform_config',
        sa.Column('stat_uptime',           sa.String(30), nullable=False, server_default='99.9%'))


def downgrade():
    op.drop_column('platform_config', 'stat_uptime')
    op.drop_column('platform_config', 'stat_transactions_day')
    op.drop_column('platform_config', 'stat_businesses')
