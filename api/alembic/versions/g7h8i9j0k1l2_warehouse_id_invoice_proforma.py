"""add warehouse_id to invoices, invoice_items, proformas, proforma_items

Revision ID: g7h8i9j0k1l2
Revises: f6g7h8i9j0k1
Down_revision: f6g7h8i9j0k1
Branch_labels: None
Depends_on: None
"""
from alembic import op
import sqlalchemy as sa


revision = 'g7h8i9j0k1l2'
down_revision = 'f6g7h8i9j0k1'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('invoices',
        sa.Column('warehouse_id', sa.String(36), sa.ForeignKey('warehouses.id'), nullable=True))
    op.create_index('ix_invoices_warehouse_id', 'invoices', ['warehouse_id'])

    # invoice_items hérite du parent après la colonne parente
    op.add_column('invoice_items',
        sa.Column('warehouse_id', sa.String(36), sa.ForeignKey('warehouses.id'), nullable=True))
    op.create_index('ix_invoice_items_warehouse_id', 'invoice_items', ['warehouse_id'])
    op.execute("""
        UPDATE invoice_items
        SET warehouse_id = (
            SELECT i.warehouse_id FROM invoices i
            WHERE i.id = invoice_items.invoice_id
        )
        WHERE warehouse_id IS NULL
    """)

    op.add_column('proformas',
        sa.Column('warehouse_id', sa.String(36), sa.ForeignKey('warehouses.id'), nullable=True))
    op.create_index('ix_proformas_warehouse_id', 'proformas', ['warehouse_id'])

    # proforma_items hérite du parent
    op.add_column('proforma_items',
        sa.Column('warehouse_id', sa.String(36), sa.ForeignKey('warehouses.id'), nullable=True))
    op.create_index('ix_proforma_items_warehouse_id', 'proforma_items', ['warehouse_id'])
    op.execute("""
        UPDATE proforma_items
        SET warehouse_id = (
            SELECT p.warehouse_id FROM proformas p
            WHERE p.id = proforma_items.proforma_id
        )
        WHERE warehouse_id IS NULL
    """)


def downgrade():
    op.drop_index('ix_proforma_items_warehouse_id', table_name='proforma_items')
    op.drop_column('proforma_items', 'warehouse_id')
    op.drop_index('ix_proformas_warehouse_id', table_name='proformas')
    op.drop_column('proformas', 'warehouse_id')
    op.drop_index('ix_invoice_items_warehouse_id', table_name='invoice_items')
    op.drop_column('invoice_items', 'warehouse_id')
    op.drop_index('ix_invoices_warehouse_id', table_name='invoices')
    op.drop_column('invoices', 'warehouse_id')
