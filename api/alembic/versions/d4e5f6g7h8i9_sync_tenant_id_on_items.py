"""add tenant_id to modifier_options and restaurant_order_items for sync isolation

Revision ID: d4e5f6g7h8i9
Revises: c3d4e5f6g7h8
Down_revision: c3d4e5f6g7h8
Branch_labels: None
Depends_on: None
"""
from alembic import op
import sqlalchemy as sa


revision = 'd4e5f6g7h8i9'
down_revision = 'c3d4e5f6g7h8'
branch_labels = None
depends_on = None


def upgrade():
    # modifier_options — hérite tenant_id de modifier_groups via group_id
    op.add_column('modifier_options',
        sa.Column('tenant_id', sa.String(36), sa.ForeignKey('tenants.id'), nullable=True))
    op.create_index('ix_modifier_options_tenant_id', 'modifier_options', ['tenant_id'])
    op.execute("""
        UPDATE modifier_options
        SET tenant_id = (
            SELECT mg.tenant_id FROM modifier_groups mg
            WHERE mg.id = modifier_options.group_id
        )
        WHERE tenant_id IS NULL
    """)

    # restaurant_order_items — hérite tenant_id de restaurant_orders via order_id
    op.add_column('restaurant_order_items',
        sa.Column('tenant_id', sa.String(36), sa.ForeignKey('tenants.id'), nullable=True))
    op.create_index('ix_restaurant_order_items_tenant_id', 'restaurant_order_items', ['tenant_id'])
    op.execute("""
        UPDATE restaurant_order_items
        SET tenant_id = (
            SELECT ro.tenant_id FROM restaurant_orders ro
            WHERE ro.id = restaurant_order_items.order_id
        )
        WHERE tenant_id IS NULL
    """)


def downgrade():
    op.drop_index('ix_restaurant_order_items_tenant_id', table_name='restaurant_order_items')
    op.drop_column('restaurant_order_items', 'tenant_id')

    op.drop_index('ix_modifier_options_tenant_id', table_name='modifier_options')
    op.drop_column('modifier_options', 'tenant_id')
