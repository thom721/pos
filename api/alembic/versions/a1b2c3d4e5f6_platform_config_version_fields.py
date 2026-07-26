"""platform_config: ajout colonnes mises à jour applicatives

Revision ID: a1b2c3d4e5f6
Revises: z0a1b2c3d4e5
Create Date: 2026-07-26
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'z0a1b2c3d4e5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return int(n) > 0


def upgrade() -> None:
    if not _col_exists("platform_config", "latest_version"):
        op.add_column("platform_config",
            sa.Column("latest_version", sa.String(20), nullable=False, server_default="0.9.0"))
    if not _col_exists("platform_config", "latest_build"):
        op.add_column("platform_config",
            sa.Column("latest_build", sa.Integer, nullable=False, server_default="1"))
    if not _col_exists("platform_config", "min_version"):
        op.add_column("platform_config",
            sa.Column("min_version", sa.String(20), nullable=False, server_default="0.9.0"))
    if not _col_exists("platform_config", "update_notes"):
        op.add_column("platform_config",
            sa.Column("update_notes", sa.Text, nullable=True))
    if not _col_exists("platform_config", "update_url"):
        op.add_column("platform_config",
            sa.Column("update_url", sa.String(512), nullable=True))
    if not _col_exists("platform_config", "force_update"):
        op.add_column("platform_config",
            sa.Column("force_update", sa.Boolean, nullable=False, server_default="0"))


def downgrade() -> None:
    for col in ("force_update", "update_url", "update_notes",
                "min_version", "latest_build", "latest_version"):
        if _col_exists("platform_config", col):
            op.drop_column("platform_config", col)
