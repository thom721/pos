"""add_performance_indexes

Revision ID: a1b2c3d4e5f6
Revises: 97b2563a8560
Create Date: 2026-06-11 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op

revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = '97b2563a8560'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── stock_movements ────────────────────────────────────────────────────────
    op.create_index('idx_sm_product_source', 'stock_movements', ['product_id', 'source_type'])
    op.create_index('idx_sm_source_id',      'stock_movements', ['source_id', 'source_type'])
    op.create_index('idx_sm_created_at',     'stock_movements', ['created_at'])

    # ── sales ──────────────────────────────────────────────────────────────────
    op.create_index('idx_sale_customer_id', 'sales', ['customer_id'])
    op.create_index('idx_sale_status',      'sales', ['status'])
    op.create_index('idx_sale_created_at',  'sales', ['created_at'])

    # ── purchases ──────────────────────────────────────────────────────────────
    op.create_index('idx_purchase_supplier_id', 'purchases', ['supplier_id'])
    op.create_index('idx_purchase_status',      'purchases', ['status'])
    op.create_index('idx_purchase_created_at',  'purchases', ['created_at'])

    # ── payments ───────────────────────────────────────────────────────────────
    op.create_index('idx_payment_reference',   'payments', ['reference_id', 'reference_type'])
    op.create_index('idx_payment_created_at',  'payments', ['created_at'])

    # ── debts ──────────────────────────────────────────────────────────────────
    op.create_index('idx_debt_reference',  'debts', ['reference_id', 'reference_type'])
    op.create_index('idx_debt_partner',    'debts', ['partner_id', 'partner_type'])
    op.create_index('idx_debt_status',     'debts', ['status'])
    op.create_index('idx_debt_created_at', 'debts', ['created_at'])


def downgrade() -> None:
    # ── debts ──────────────────────────────────────────────────────────────────
    op.drop_index('idx_debt_created_at', table_name='debts')
    op.drop_index('idx_debt_status',     table_name='debts')
    op.drop_index('idx_debt_partner',    table_name='debts')
    op.drop_index('idx_debt_reference',  table_name='debts')

    # ── payments ───────────────────────────────────────────────────────────────
    op.drop_index('idx_payment_created_at',  table_name='payments')
    op.drop_index('idx_payment_reference',   table_name='payments')

    # ── purchases ──────────────────────────────────────────────────────────────
    op.drop_index('idx_purchase_created_at',  table_name='purchases')
    op.drop_index('idx_purchase_status',      table_name='purchases')
    op.drop_index('idx_purchase_supplier_id', table_name='purchases')

    # ── sales ──────────────────────────────────────────────────────────────────
    op.drop_index('idx_sale_created_at',  table_name='sales')
    op.drop_index('idx_sale_status',      table_name='sales')
    op.drop_index('idx_sale_customer_id', table_name='sales')

    # ── stock_movements ────────────────────────────────────────────────────────
    op.drop_index('idx_sm_created_at',     table_name='stock_movements')
    op.drop_index('idx_sm_source_id',      table_name='stock_movements')
    op.drop_index('idx_sm_product_source', table_name='stock_movements')
