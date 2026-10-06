"""add warehouse_id to discounts (rabais par dépôt, NULL = tous les dépôts)

Fusionne aussi les deux têtes existantes (affiliate, app_config logo) en une
seule : cette révision a les deux comme parents.

Revision ID: e7c1a9d2f4b8
Revises: a1f9c3e7b2d6, d5e2f8a1b6c9
Create Date: 2026-10-06 10:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'e7c1a9d2f4b8'
down_revision: Union[str, Sequence[str], None] = ('a1f9c3e7b2d6', 'd5e2f8a1b6c9')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(bind, table: str, column: str) -> bool:
    return column in {c["name"] for c in _inspect(bind).get_columns(table)}


def upgrade() -> None:
    bind = op.get_bind()
    if not _has_column(bind, "discounts", "warehouse_id"):
        op.add_column("discounts", sa.Column("warehouse_id", sa.String(36), nullable=True))
        op.create_index("ix_discounts_warehouse_id", "discounts", ["warehouse_id"])
        op.create_foreign_key(
            "fk_discounts_warehouse_id", "discounts", "warehouses",
            ["warehouse_id"], ["id"], ondelete="CASCADE",
        )


def downgrade() -> None:
    bind = op.get_bind()
    if _has_column(bind, "discounts", "warehouse_id"):
        op.drop_constraint("fk_discounts_warehouse_id", "discounts", type_="foreignkey")
        op.drop_index("ix_discounts_warehouse_id", table_name="discounts")
        op.drop_column("discounts", "warehouse_id")
