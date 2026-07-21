"""add warehouse_id to products

Revision ID: h8i9j0k1l2m3
Revises: g7h8i9j0k1l2
Down_revision: g7h8i9j0k1l2
Branch_labels: None
Depends_on: None
"""
from alembic import op
import sqlalchemy as sa


revision = 'h8i9j0k1l2m3'
down_revision = 'g7h8i9j0k1l2'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('products',
        sa.Column('warehouse_id', sa.String(36), sa.ForeignKey('warehouses.id'), nullable=True))
    op.create_index('ix_products_warehouse_id', 'products', ['warehouse_id'])


def downgrade():
    op.drop_index('ix_products_warehouse_id', table_name='products')
    op.drop_column('products', 'warehouse_id')
