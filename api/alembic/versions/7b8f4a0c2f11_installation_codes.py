"""add installation_codes table

Revision ID: 7b8f4a0c2f11
Revises: z0a1b2c3d4e5
Create Date: 2026-07-25 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

revision = "7b8f4a0c2f11"
down_revision = "z0a1b2c3d4e5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "installation_codes",
        sa.Column("id",           sa.String(36),  primary_key=True),
        sa.Column("code",         sa.String(20),  nullable=False, unique=True),
        sa.Column("tenant_id",    sa.String(36),  sa.ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("warehouse_id", sa.String(36),  sa.ForeignKey("warehouses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at",   sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_installation_codes_code",      "installation_codes", ["code"])
    op.create_index("ix_installation_codes_tenant_id", "installation_codes", ["tenant_id"])


def downgrade() -> None:
    op.drop_table("installation_codes")
