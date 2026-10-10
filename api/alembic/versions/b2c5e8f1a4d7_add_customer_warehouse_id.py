"""add customer.warehouse_id

Revision ID: b2c5e8f1a4d7
Revises: a1b4c7d9e3f2
Create Date: 2026-10-10
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'b2c5e8f1a4d7'
down_revision: Union[str, Sequence[str], None] = 'a1b4c7d9e3f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    cols = [c["name"] for c in _inspect(bind).get_columns("customers")]
    if "warehouse_id" in cols:
        return
    op.add_column(
        "customers",
        sa.Column("warehouse_id", sa.String(36), sa.ForeignKey("warehouses.id", ondelete="CASCADE"), nullable=True),
    )
    op.create_index("ix_customers_warehouse_id", "customers", ["warehouse_id"])


def downgrade() -> None:
    bind = op.get_bind()
    cols = [c["name"] for c in _inspect(bind).get_columns("customers")]
    if "warehouse_id" in cols:
        op.drop_index("ix_customers_warehouse_id", table_name="customers")
        op.drop_column("customers", "warehouse_id")
