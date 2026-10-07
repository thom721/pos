"""add product.is_service

Revision ID: a1b4c7d9e3f2
Revises: f3a8d1c6e2b9
Create Date: 2026-10-07
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'a1b4c7d9e3f2'
down_revision: Union[str, Sequence[str], None] = 'f3a8d1c6e2b9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    cols = [c["name"] for c in _inspect(bind).get_columns("products")]
    if "is_service" in cols:
        return
    op.add_column(
        "products",
        sa.Column("is_service", sa.Boolean(), nullable=False, server_default=sa.false()),
    )


def downgrade() -> None:
    bind = op.get_bind()
    cols = [c["name"] for c in _inspect(bind).get_columns("products")]
    if "is_service" in cols:
        op.drop_column("products", "is_service")
