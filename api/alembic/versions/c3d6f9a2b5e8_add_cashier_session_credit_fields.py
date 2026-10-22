"""add cashier_sessions.total_credit_sold / total_debt_collected

Revision ID: c3d6f9a2b5e8
Revises: b2c5e8f1a4d7
Create Date: 2026-10-22
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'c3d6f9a2b5e8'
down_revision: Union[str, Sequence[str], None] = 'b2c5e8f1a4d7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    cols = [c["name"] for c in _inspect(bind).get_columns("cashier_sessions")]
    if "total_credit_sold" not in cols:
        op.add_column(
            "cashier_sessions",
            sa.Column("total_credit_sold", sa.Numeric(12, 2), nullable=True),
        )
    if "total_debt_collected" not in cols:
        op.add_column(
            "cashier_sessions",
            sa.Column("total_debt_collected", sa.Numeric(12, 2), nullable=True),
        )


def downgrade() -> None:
    bind = op.get_bind()
    cols = [c["name"] for c in _inspect(bind).get_columns("cashier_sessions")]
    if "total_debt_collected" in cols:
        op.drop_column("cashier_sessions", "total_debt_collected")
    if "total_credit_sold" in cols:
        op.drop_column("cashier_sessions", "total_credit_sold")
