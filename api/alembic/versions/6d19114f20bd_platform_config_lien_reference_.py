"""platform_config: lien reference installeur serveur windows

Revision ID: 6d19114f20bd
Revises: 6bbeb7d871f3
Create Date: 2026-08-09 15:15:48.834181

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6d19114f20bd'
down_revision: Union[str, Sequence[str], None] = '6bbeb7d871f3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return int(n) > 0


def upgrade() -> None:
    if not _col_exists("platform_config", "update_url_windows_server"):
        op.add_column("platform_config",
            sa.Column("update_url_windows_server", sa.String(512), nullable=True))


def downgrade() -> None:
    if _col_exists("platform_config", "update_url_windows_server"):
        op.drop_column("platform_config", "update_url_windows_server")
