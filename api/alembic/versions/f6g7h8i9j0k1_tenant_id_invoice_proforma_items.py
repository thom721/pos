"""add tenant_id to invoice_items and proforma_items

Revision ID: f6g7h8i9j0k1
Revises: e5f6g7h8i9j0
Down_revision: e5f6g7h8i9j0
Branch_labels: None
Depends_on: None
"""
from alembic import op
import sqlalchemy as sa


revision = 'f6g7h8i9j0k1'
down_revision = 'e5f6g7h8i9j0'
branch_labels = None
depends_on = None


def upgrade():
    # invoice_items — hérite tenant_id de invoices via invoice_id
    op.add_column('invoice_items',
        sa.Column('tenant_id', sa.String(36), sa.ForeignKey('tenants.id'), nullable=True))
    op.create_index('ix_invoice_items_tenant_id', 'invoice_items', ['tenant_id'])
    op.execute("""
        UPDATE invoice_items
        SET tenant_id = (
            SELECT i.tenant_id FROM invoices i
            WHERE i.id = invoice_items.invoice_id
        )
        WHERE tenant_id IS NULL
    """)

    # proforma_items — hérite tenant_id de proformas via proforma_id
    op.add_column('proforma_items',
        sa.Column('tenant_id', sa.String(36), sa.ForeignKey('tenants.id'), nullable=True))
    op.create_index('ix_proforma_items_tenant_id', 'proforma_items', ['tenant_id'])
    op.execute("""
        UPDATE proforma_items
        SET tenant_id = (
            SELECT p.tenant_id FROM proformas p
            WHERE p.id = proforma_items.proforma_id
        )
        WHERE tenant_id IS NULL
    """)


def downgrade():
    op.drop_index('ix_proforma_items_tenant_id', table_name='proforma_items')
    op.drop_column('proforma_items', 'tenant_id')

    op.drop_index('ix_invoice_items_tenant_id', table_name='invoice_items')
    op.drop_column('invoice_items', 'tenant_id')
