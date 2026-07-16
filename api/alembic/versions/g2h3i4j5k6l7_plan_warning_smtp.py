"""plan_warning_smtp — last_warning_sent_at sur tenants, smtp sur platform_config

Revision ID: g2h3i4j5k6l7
Revises: f1a2b3c4d5e6
Create Date: 2026-07-16 18:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = 'g2h3i4j5k6l7'
down_revision = 'f1a2b3c4d5e6'
branch_labels = None
depends_on = None


def _col_exists(table: str, col: str) -> bool:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())
    return col in {c["name"] for c in insp.get_columns(table)}


def upgrade():
    if not _col_exists("tenants", "last_warning_sent_at"):
        op.add_column("tenants",
            sa.Column("last_warning_sent_at", sa.DateTime(timezone=True), nullable=True))

    for col, typ, default in [
        ("smtp_host",     sa.String(200), ""),
        ("smtp_user",     sa.String(200), ""),
        ("smtp_password", sa.String(255), ""),
        ("smtp_from",     sa.String(200), ""),
    ]:
        if not _col_exists("platform_config", col):
            op.add_column("platform_config",
                sa.Column(col, typ, nullable=False, server_default=default))

    if not _col_exists("platform_config", "smtp_port"):
        op.add_column("platform_config",
            sa.Column("smtp_port", sa.Integer(), nullable=False, server_default="587"))


def downgrade():
    pass
