"""add warehouse_id to modifier_options and restaurant_order_items

Revision ID: e5f6g7h8i9j0
Revises: d4e5f6g7h8i9
Down_revision: d4e5f6g7h8i9
Branch_labels: None
Depends_on: None
"""
from alembic import op
import sqlalchemy as sa


revision = 'e5f6g7h8i9j0'
down_revision = 'd4e5f6g7h8i9'
branch_labels = None
depends_on = None


def upgrade():
    # modifier_options — hérite warehouse_id de modifier_groups via group_id
    op.add_column('modifier_options',
        sa.Column('warehouse_id', sa.String(36), sa.ForeignKey('warehouses.id'), nullable=True))
    op.create_index('ix_modifier_options_warehouse_id', 'modifier_options', ['warehouse_id'])
    op.execute("""
        UPDATE modifier_options
        SET warehouse_id = (
            SELECT mg.warehouse_id FROM modifier_groups mg
            WHERE mg.id = modifier_options.group_id
        )
        WHERE warehouse_id IS NULL
    """)

    # restaurant_order_items — hérite warehouse_id de restaurant_orders via order_id
    op.add_column('restaurant_order_items',
        sa.Column('warehouse_id', sa.String(36), sa.ForeignKey('warehouses.id'), nullable=True))
    op.create_index('ix_restaurant_order_items_warehouse_id', 'restaurant_order_items', ['warehouse_id'])
    op.execute("""
        UPDATE restaurant_order_items
        SET warehouse_id = (
            SELECT ro.warehouse_id FROM restaurant_orders ro
            WHERE ro.id = restaurant_order_items.order_id
        )
        WHERE warehouse_id IS NULL
    """)


def downgrade():
    op.drop_index('ix_restaurant_order_items_warehouse_id', table_name='restaurant_order_items')
    op.drop_column('restaurant_order_items', 'warehouse_id')

    op.drop_index('ix_modifier_options_warehouse_id', table_name='modifier_options')
    op.drop_column('modifier_options', 'warehouse_id')
