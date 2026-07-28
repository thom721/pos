"""platform_config: payment methods enabled flags

Revision ID: b2c3d4e5f6g7
Revises: a1b2c3d4e5f6
Create Date: 2026-07-24

Nouveaux champs :
  platform_config : cash_enabled, moncash_enabled, natcash_enabled, card_enabled (BOOL, default 1)
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect

revision = 'b2c3d4e5f6g7'
down_revision = 'a1b2c3d4e5f6'
branch_labels = None
depends_on = None


def _has_column(bind, table: str, column: str) -> bool:
    return column in {c["name"] for c in _inspect(bind).get_columns(table)}


def upgrade():
    bind = op.get_bind()
    with op.batch_alter_table('platform_config') as batch:
        if not _has_column(bind, 'platform_config', 'cash_enabled'):
            batch.add_column(sa.Column(
                'cash_enabled', sa.Boolean(), nullable=False, server_default=sa.text('1'),
            ))
        if not _has_column(bind, 'platform_config', 'moncash_enabled'):
            batch.add_column(sa.Column(
                'moncash_enabled', sa.Boolean(), nullable=False, server_default=sa.text('1'),
            ))
        if not _has_column(bind, 'platform_config', 'natcash_enabled'):
            batch.add_column(sa.Column(
                'natcash_enabled', sa.Boolean(), nullable=False, server_default=sa.text('1'),
            ))
        if not _has_column(bind, 'platform_config', 'card_enabled'):
            batch.add_column(sa.Column(
                'card_enabled', sa.Boolean(), nullable=False, server_default=sa.text('1'),
            ))


def downgrade():
    bind = op.get_bind()
    with op.batch_alter_table('platform_config') as batch:
        if _has_column(bind, 'platform_config', 'card_enabled'):
            batch.drop_column('card_enabled')
        if _has_column(bind, 'platform_config', 'natcash_enabled'):
            batch.drop_column('natcash_enabled')
        if _has_column(bind, 'platform_config', 'moncash_enabled'):
            batch.drop_column('moncash_enabled')
        if _has_column(bind, 'platform_config', 'cash_enabled'):
            batch.drop_column('cash_enabled')
