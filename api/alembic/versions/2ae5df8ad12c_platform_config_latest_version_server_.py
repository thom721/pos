"""platform_config: latest_version_server pour verification serveur

Revision ID: 2ae5df8ad12c
Revises: 6d19114f20bd
Create Date: 2026-08-11 09:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '2ae5df8ad12c'
down_revision: Union[str, Sequence[str], None] = '6d19114f20bd'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return int(n) > 0


def upgrade() -> None:
    if not _col_exists("platform_config", "latest_version_server"):
        op.add_column("platform_config",
            sa.Column("latest_version_server", sa.String(20), nullable=True))


def downgrade() -> None:
    if _col_exists("platform_config", "latest_version_server"):
        op.drop_column("platform_config", "latest_version_server")
