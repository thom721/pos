"""add stat columns to platform_config

Revision ID: i9j0k1l2m3n4
Revises: h8i9j0k1l2m3
Down_revision: h8i9j0k1l2m3
Branch_labels: None
Depends_on: None
"""
from alembic import op
import sqlalchemy as sa


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade():
    if not _col_exists('platform_config', 'stat_businesses'):
        op.add_column('platform_config',
            sa.Column('stat_businesses', sa.String(30), nullable=False,
                      server_default=sa.text("'500+'")))
    if not _col_exists('platform_config', 'stat_transactions_day'):
        op.add_column('platform_config',
            sa.Column('stat_transactions_day', sa.String(30), nullable=False,
                      server_default=sa.text("'10k+'")))
    if not _col_exists('platform_config', 'stat_uptime'):
        op.add_column('platform_config',
            sa.Column('stat_uptime', sa.String(30), nullable=False,
                      server_default=sa.text("'99.9%'")))


def downgrade():
    op.drop_column('platform_config', 'stat_uptime')
    op.drop_column('platform_config', 'stat_transactions_day')
    op.drop_column('platform_config', 'stat_businesses')
