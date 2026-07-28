"""add discounts table + discount columns on sales/sale_items

Revision ID: 3d6ef4310920
Revises: e5ce18f81b73
Create Date: 2026-07-28 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = '3d6ef4310920'
down_revision: Union[str, Sequence[str], None] = 'e5ce18f81b73'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_table(bind, name: str) -> bool:
    return name in _inspect(bind).get_table_names()


def _has_column(bind, table: str, column: str) -> bool:
    if not _has_table(bind, table):
        return False
    return column in {c["name"] for c in _inspect(bind).get_columns(table)}


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()

    if not _has_table(bind, "discounts"):
        op.create_table(
            "discounts",
            sa.Column("id", sa.String(36), primary_key=True),
            sa.Column("tenant_id", sa.String(36), sa.ForeignKey("tenants.id"), nullable=True),
            sa.Column("name", sa.String(255), nullable=False),
            sa.Column("type", sa.Enum("percentage", "fixed", name="discount_type"), nullable=False),
            sa.Column("value", sa.Numeric(12, 2), nullable=False),
            sa.Column(
                "scope",
                sa.Enum("receipt", "item", "both", name="discount_scope"),
                nullable=False,
                server_default="both",
            ),
            sa.Column("is_automatic", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
            sa.Column("schedule_days", sa.String(20), nullable=True),
            sa.Column("schedule_start", sa.Time(), nullable=True),
            sa.Column("schedule_end", sa.Time(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("tenant_id", "name", name="uq_discount_tenant_name"),
        )
        op.create_index("ix_discounts_tenant_id", "discounts", ["tenant_id"])

    if not _has_column(bind, "sales", "discount_id"):
        with op.batch_alter_table("sales") as batch:
            batch.add_column(sa.Column(
                "discount_id", sa.String(36),
                sa.ForeignKey("discounts.id", name="fk_sales_discount_id"),
                nullable=True,
            ))

    if not _has_column(bind, "sale_items", "discount"):
        with op.batch_alter_table("sale_items") as batch:
            batch.add_column(sa.Column("discount", sa.Numeric(12, 2), server_default="0"))

    if not _has_column(bind, "sale_items", "discount_id"):
        with op.batch_alter_table("sale_items") as batch:
            batch.add_column(sa.Column(
                "discount_id", sa.String(36),
                sa.ForeignKey("discounts.id", name="fk_sale_items_discount_id"),
                nullable=True,
            ))


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()

    if _has_column(bind, "sale_items", "discount_id"):
        with op.batch_alter_table("sale_items") as batch:
            batch.drop_column("discount_id")

    if _has_column(bind, "sale_items", "discount"):
        with op.batch_alter_table("sale_items") as batch:
            batch.drop_column("discount")

    if _has_column(bind, "sales", "discount_id"):
        with op.batch_alter_table("sales") as batch:
            batch.drop_column("discount_id")

    if _has_table(bind, "discounts"):
        op.drop_index("ix_discounts_tenant_id", table_name="discounts")
        op.drop_table("discounts")
        if bind.dialect.name != "sqlite":
            op.execute("DROP TYPE IF EXISTS discount_type")
            op.execute("DROP TYPE IF EXISTS discount_scope")
