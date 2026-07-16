"""platform_config_admin_credentials

Revision ID: d7e8f9a0b1c2
Revises: a4d523bd5f01
Create Date: 2026-06-16 10:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'd7e8f9a0b1c2'
down_revision: Union[str, None] = 'a4d523bd5f01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
    if not _col_exists('platform_config', 'admin_email'):
        op.add_column('platform_config',
            sa.Column('admin_email', sa.String(200), nullable=False, server_default=''))
    if not _col_exists('platform_config', 'admin_password_hash'):
        op.add_column('platform_config',
            sa.Column('admin_password_hash', sa.String(255), nullable=False, server_default=''))


def downgrade() -> None:
    op.drop_column('platform_config', 'admin_password_hash')
    op.drop_column('platform_config', 'admin_email')
