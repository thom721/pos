"""add product warehouse price

Revision ID: 81f87741e746
Revises: 1c91ed10a01d
Create Date: 2026-07-31 16:25:03.972543

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '81f87741e746'
down_revision: Union[str, Sequence[str], None] = '1c91ed10a01d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "product_warehouse_prices",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("tenant_id", sa.String(36), sa.ForeignKey("tenants.id"), nullable=True, index=True),
        sa.Column("product_id", sa.String(36), sa.ForeignKey("products.id"), nullable=False, index=True),
        sa.Column("warehouse_id", sa.String(36), sa.ForeignKey("warehouses.id"), nullable=False, index=True),
        sa.Column("sale_price", sa.Numeric(12, 2), nullable=False),
        sa.UniqueConstraint("product_id", "warehouse_id", name="uq_product_warehouse_price"),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table("product_warehouse_prices")
