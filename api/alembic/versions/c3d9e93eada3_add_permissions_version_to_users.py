"""add permissions_version to users

Revision ID: c3d9e93eada3
Revises: 99a0453781bc
Create Date: 2026-07-28 13:47:51.853975

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'c3d9e93eada3'
down_revision: Union[str, Sequence[str], None] = '99a0453781bc'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(bind, table: str, column: str) -> bool:
    return column in {c["name"] for c in _inspect(bind).get_columns(table)}


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()
    if not _has_column(bind, "users", "permissions_version"):
        with op.batch_alter_table("users") as batch:
            batch.add_column(sa.Column(
                "permissions_version", sa.Integer(), nullable=False, server_default="0",
            ))


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    if _has_column(bind, "users", "permissions_version"):
        with op.batch_alter_table("users") as batch:
            batch.drop_column("permissions_version")
