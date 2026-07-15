"""add_reconciliation_to_cashier_session

Revision ID: fd860b506c43
Revises: a4dafac8ce4b
Create Date: 2026-07-15 14:47:43.077759

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'fd860b506c43'
down_revision: Union[str, Sequence[str], None] = 'a4dafac8ce4b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('cashier_sessions', sa.Column('total_cash_sales',         sa.Numeric(12, 2), nullable=True))
    op.add_column('cashier_sessions', sa.Column('total_card_sales',         sa.Numeric(12, 2), nullable=True))
    op.add_column('cashier_sessions', sa.Column('total_mobile_sales',       sa.Numeric(12, 2), nullable=True))
    op.add_column('cashier_sessions', sa.Column('total_bank_sales',         sa.Numeric(12, 2), nullable=True))
    op.add_column('cashier_sessions', sa.Column('total_refunds_cash',       sa.Numeric(12, 2), nullable=True))
    op.add_column('cashier_sessions', sa.Column('expected_closing_balance', sa.Numeric(12, 2), nullable=True))
    op.add_column('cashier_sessions', sa.Column('cash_difference',          sa.Numeric(12, 2), nullable=True))


def downgrade() -> None:
    op.drop_column('cashier_sessions', 'cash_difference')
    op.drop_column('cashier_sessions', 'expected_closing_balance')
    op.drop_column('cashier_sessions', 'total_refunds_cash')
    op.drop_column('cashier_sessions', 'total_bank_sales')
    op.drop_column('cashier_sessions', 'total_mobile_sales')
    op.drop_column('cashier_sessions', 'total_card_sales')
    op.drop_column('cashier_sessions', 'total_cash_sales')
