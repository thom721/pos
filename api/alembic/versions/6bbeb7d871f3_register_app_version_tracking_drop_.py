"""register app version tracking + drop platform_config min_version

Revision ID: 6bbeb7d871f3
Revises: d55f7b8bc650
Create Date: 2026-08-09 10:22:32.825370

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6bbeb7d871f3'
down_revision: Union[str, Sequence[str], None] = 'd55f7b8bc650'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return int(n) > 0


def upgrade() -> None:
    if not _col_exists("pos_registers", "app_version"):
        op.add_column("pos_registers",
            sa.Column("app_version", sa.String(20), nullable=True))
    if not _col_exists("pos_registers", "app_build"):
        op.add_column("pos_registers",
            sa.Column("app_build", sa.Integer, nullable=True))
    # min_version : jamais lu côté client (comparaison réelle basée sur
    # latest_build/force_update uniquement) — champ mort, retiré.
    if _col_exists("platform_config", "min_version"):
        op.drop_column("platform_config", "min_version")


def downgrade() -> None:
    if not _col_exists("platform_config", "min_version"):
        op.add_column("platform_config",
            sa.Column("min_version", sa.String(20), nullable=False, server_default="0.9.0"))
    if _col_exists("pos_registers", "app_build"):
        op.drop_column("pos_registers", "app_build")
    if _col_exists("pos_registers", "app_version"):
        op.drop_column("pos_registers", "app_version")
