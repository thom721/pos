"""add report_columns to app_config

Revision ID: db8541247338
Revises: 7408f808927a
Create Date: 2026-07-28 11:19:48.380435

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'db8541247338'
down_revision: Union[str, Sequence[str], None] = '7408f808927a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(bind, table: str, column: str) -> bool:
    return column in {c["name"] for c in _inspect(bind).get_columns(table)}


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()
    if not _has_column(bind, "app_config", "report_columns"):
        op.add_column("app_config", sa.Column("report_columns", sa.Text(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    if _has_column(bind, "app_config", "report_columns"):
        op.drop_column("app_config", "report_columns")
