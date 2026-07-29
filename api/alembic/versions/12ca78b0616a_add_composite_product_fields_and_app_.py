"""add composite product fields and app config trigger

Revision ID: 12ca78b0616a
Revises: 8fa9aca853ef
Create Date: 2026-07-29 06:17:57.984485

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '12ca78b0616a'
down_revision: Union[str, Sequence[str], None] = '8fa9aca853ef'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()
    prod_cols = {c["name"] for c in sa.inspect(bind).get_columns("products")}
    with op.batch_alter_table("products") as batch:
        if "component_product_id" not in prod_cols:
            batch.add_column(sa.Column("component_product_id", sa.String(36), nullable=True))
            batch.create_foreign_key(
                "fk_product_component", "products",
                ["component_product_id"], ["id"],
            )
        if "component_quantity" not in prod_cols:
            batch.add_column(sa.Column("component_quantity", sa.Numeric(12, 4), nullable=True))

    cfg_cols = {c["name"] for c in sa.inspect(bind).get_columns("app_config")}
    if "composite_stock_trigger" not in cfg_cols:
        with op.batch_alter_table("app_config") as batch:
            batch.add_column(
                sa.Column("composite_stock_trigger", sa.String(20), nullable=False, server_default="manual"),
            )


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    cfg_cols = {c["name"] for c in sa.inspect(bind).get_columns("app_config")}
    if "composite_stock_trigger" in cfg_cols:
        with op.batch_alter_table("app_config") as batch:
            batch.drop_column("composite_stock_trigger")

    prod_cols = {c["name"] for c in sa.inspect(bind).get_columns("products")}
    with op.batch_alter_table("products") as batch:
        if "component_quantity" in prod_cols:
            batch.drop_column("component_quantity")
        if "component_product_id" in prod_cols:
            batch.drop_constraint("fk_product_component", type_="foreignkey")
            batch.drop_column("component_product_id")
