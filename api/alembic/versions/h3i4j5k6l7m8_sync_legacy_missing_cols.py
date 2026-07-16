"""sync_legacy_missing_cols — colonnes présentes dans l'ancienne chaîne alembic
mais absentes de api/alembic/ (idempotent)

Revision ID: h3i4j5k6l7m8
Revises: g2h3i4j5k6l7
Create Date: 2026-07-16

Colonnes manquantes issues de :
  - ca853a4cc1f8  billing_payments.months
  - fd860b506c43  cashier_sessions réconciliation (7 colonnes)
  - 24f7d83b5055  users.must_change_password
  - 4dc5c4ca1d2e  purchase_items.remaining_qty
  - 97b2563a8560  payments.method / note / payment_methode
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

revision: str = 'h3i4j5k6l7m8'
down_revision: Union[str, None] = 'g2h3i4j5k6l7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
    # ── billing_payments.months ───────────────────────────────────────────────
    if not _col_exists('billing_payments', 'months'):
        op.add_column('billing_payments',
            sa.Column('months', sa.Integer(), nullable=False, server_default='1'))

    # ── cashier_sessions : réconciliation ─────────────────────────────────────
    for col in ('total_cash_sales', 'total_card_sales', 'total_mobile_sales',
                'total_bank_sales', 'total_refunds_cash',
                'expected_closing_balance', 'cash_difference'):
        if not _col_exists('cashier_sessions', col):
            op.add_column('cashier_sessions',
                sa.Column(col, sa.Numeric(12, 2), nullable=True))

    # ── users.must_change_password ────────────────────────────────────────────
    if not _col_exists('users', 'must_change_password'):
        op.add_column('users',
            sa.Column('must_change_password', sa.Boolean(),
                      nullable=False, server_default='0'))

    # ── purchase_items.remaining_qty ──────────────────────────────────────────
    if not _col_exists('purchase_items', 'remaining_qty'):
        op.add_column('purchase_items',
            sa.Column('remaining_qty', sa.Float(), nullable=True))

    # ── payments : method / note / payment_methode ────────────────────────────
    if not _col_exists('payments', 'method'):
        op.add_column('payments',
            sa.Column('method', sa.String(20), nullable=True))
    if not _col_exists('payments', 'note'):
        op.add_column('payments',
            sa.Column('note', sa.Text(), nullable=True))
    if not _col_exists('payments', 'payment_methode'):
        op.add_column('payments',
            sa.Column('payment_methode',
                      mysql.ENUM('CASH', 'BANK', 'MOBILE'), nullable=True))


def downgrade() -> None:
    op.drop_column('payments', 'payment_methode')
    op.drop_column('payments', 'note')
    op.drop_column('payments', 'method')
    op.drop_column('purchase_items', 'remaining_qty')
    op.drop_column('users', 'must_change_password')
    for col in ('cash_difference', 'expected_closing_balance', 'total_refunds_cash',
                'total_bank_sales', 'total_mobile_sales', 'total_card_sales',
                'total_cash_sales'):
        op.drop_column('cashier_sessions', col)
    op.drop_column('billing_payments', 'months')
