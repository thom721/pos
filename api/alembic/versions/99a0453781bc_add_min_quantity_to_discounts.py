"""add min_quantity to discounts

Revision ID: 99a0453781bc
Revises: db8541247338
Create Date: 2026-07-28 13:12:02.866836

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = '99a0453781bc'
down_revision: Union[str, Sequence[str], None] = 'db8541247338'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(bind, table: str, column: str) -> bool:
    return column in {c["name"] for c in _inspect(bind).get_columns(table)}


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()
    if not _has_column(bind, "discounts", "min_quantity"):
        op.add_column("discounts", sa.Column("min_quantity", sa.Numeric(12, 2), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    if _has_column(bind, "discounts", "min_quantity"):
        op.drop_column("discounts", "min_quantity")
