"""depot pricing: max_depots on tenants, price_per_extra_depot on platform_config

Revision ID: n8o9p0q1r2s3
Revises: m7n8o9p0q1r2
Create Date: 2026-07-16
"""
from alembic import op
import sqlalchemy as sa


revision = 'n8o9p0q1r2s3'
down_revision = 'm7n8o9p0q1r2'
branch_labels = None
depends_on = None


def _col_exists(table: str, column: str) -> bool:
    conn = op.get_bind()
    dialect = conn.dialect.name
    if dialect == "mysql":
        row = conn.execute(sa.text(
            "SELECT COUNT(*) FROM information_schema.COLUMNS "
            "WHERE TABLE_SCHEMA = DATABASE() "
            "AND TABLE_NAME = :t AND COLUMN_NAME = :c"
        ), {"t": table, "c": column}).scalar()
        return row > 0
    # SQLite
    rows = conn.execute(sa.text(f"PRAGMA table_info({table})")).fetchall()
    return any(r[1] == column for r in rows)


def upgrade():
    if not _col_exists("tenants", "max_depots"):
        op.add_column("tenants", sa.Column(
            "max_depots", sa.Integer(), nullable=False, server_default="1"
        ))

    if not _col_exists("platform_config", "price_per_extra_depot_htg"):
        op.add_column("platform_config", sa.Column(
            "price_per_extra_depot_htg", sa.Numeric(10, 2),
            nullable=False, server_default="500.00"
        ))

    if not _col_exists("platform_config", "price_per_extra_depot_usd"):
        op.add_column("platform_config", sa.Column(
            "price_per_extra_depot_usd", sa.Numeric(10, 2),
            nullable=False, server_default="4.00"
        ))


def downgrade():
    conn = op.get_bind()
    if conn.dialect.name != "sqlite":
        if _col_exists("platform_config", "price_per_extra_depot_usd"):
            op.drop_column("platform_config", "price_per_extra_depot_usd")
        if _col_exists("platform_config", "price_per_extra_depot_htg"):
            op.drop_column("platform_config", "price_per_extra_depot_htg")
        if _col_exists("tenants", "max_depots"):
            op.drop_column("tenants", "max_depots")
