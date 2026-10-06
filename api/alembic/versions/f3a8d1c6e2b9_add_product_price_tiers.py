"""add product_price_tiers (paliers de prix par produit et par dépôt)

Revision ID: f3a8d1c6e2b9
Revises: e7c1a9d2f4b8
Create Date: 2026-10-06 12:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'f3a8d1c6e2b9'
down_revision: Union[str, Sequence[str], None] = 'e7c1a9d2f4b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    if _inspect(bind).has_table("product_price_tiers"):
        return
    op.create_table(
        "product_price_tiers",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("tenant_id", sa.String(36), sa.ForeignKey("tenants.id"), nullable=True),
        sa.Column("product_id", sa.String(36), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("warehouse_id", sa.String(36), sa.ForeignKey("warehouses.id"), nullable=False),
        sa.Column("min_quantity", sa.Numeric(12, 2), nullable=False),
        sa.Column("price", sa.Numeric(12, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("product_id", "warehouse_id", "min_quantity", name="uq_product_warehouse_tier"),
    )
    op.create_index("ix_product_price_tiers_tenant_id", "product_price_tiers", ["tenant_id"])
    op.create_index("ix_product_price_tiers_product_id", "product_price_tiers", ["product_id"])
    op.create_index("ix_product_price_tiers_warehouse_id", "product_price_tiers", ["warehouse_id"])


def downgrade() -> None:
    bind = op.get_bind()
    if _inspect(bind).has_table("product_price_tiers"):
        op.drop_table("product_price_tiers")
