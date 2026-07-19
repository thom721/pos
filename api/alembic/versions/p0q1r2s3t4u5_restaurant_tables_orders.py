"""restaurant: tables et commandes par table

Revision ID: p0q1r2s3t4u5
Revises: o9p0q1r2s3t4
Create Date: 2026-07-18
"""
from alembic import op
import sqlalchemy as sa

revision = 'p0q1r2s3t4u5'
down_revision = 'o9p0q1r2s3t4'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'restaurant_tables',
        sa.Column('id',           sa.String(36),  primary_key=True),
        sa.Column('tenant_id',    sa.String(36),  nullable=False),
        sa.Column('warehouse_id', sa.String(36),  nullable=True),
        sa.Column('name',         sa.String(100), nullable=False),
        sa.Column('capacity',     sa.Integer,     default=4),
        sa.Column('status',       sa.Enum('free', 'occupied', 'reserved',
                                          name='restaurant_table_status'),
                  nullable=False, server_default='free'),
        sa.Column('created_at',   sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
        sa.Column('updated_at',   sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index('ix_restaurant_tables_tenant_id',    'restaurant_tables', ['tenant_id'])
    op.create_index('ix_restaurant_tables_warehouse_id', 'restaurant_tables', ['warehouse_id'])
    op.create_foreign_key('fk_rtables_tenant',    'restaurant_tables', 'tenants',    ['tenant_id'],    ['id'], ondelete='CASCADE')
    op.create_foreign_key('fk_rtables_warehouse', 'restaurant_tables', 'warehouses', ['warehouse_id'], ['id'], ondelete='SET NULL')

    op.create_table(
        'restaurant_orders',
        sa.Column('id',           sa.String(36), primary_key=True),
        sa.Column('tenant_id',    sa.String(36), nullable=False),
        sa.Column('warehouse_id', sa.String(36), nullable=True),
        sa.Column('table_id',     sa.String(36), nullable=False),
        sa.Column('cashier_id',   sa.String(36), nullable=True),
        sa.Column('status',       sa.Enum('open', 'sent_to_kitchen', 'ready', 'closed',
                                          name='restaurant_order_status'),
                  nullable=False, server_default='open'),
        sa.Column('notes',        sa.Text,       nullable=True),
        sa.Column('sale_id',      sa.String(36), nullable=True),
        sa.Column('created_at',   sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
        sa.Column('updated_at',   sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index('ix_restaurant_orders_tenant_id',    'restaurant_orders', ['tenant_id'])
    op.create_index('ix_restaurant_orders_warehouse_id', 'restaurant_orders', ['warehouse_id'])
    op.create_index('ix_restaurant_orders_table_id',     'restaurant_orders', ['table_id'])
    op.create_foreign_key('fk_rorders_tenant',    'restaurant_orders', 'tenants',           ['tenant_id'],    ['id'], ondelete='CASCADE')
    op.create_foreign_key('fk_rorders_warehouse', 'restaurant_orders', 'warehouses',        ['warehouse_id'], ['id'], ondelete='SET NULL')
    op.create_foreign_key('fk_rorders_table',     'restaurant_orders', 'restaurant_tables', ['table_id'],     ['id'], ondelete='CASCADE')
    op.create_foreign_key('fk_rorders_sale',      'restaurant_orders', 'sales',             ['sale_id'],      ['id'], ondelete='SET NULL')

    op.create_table(
        'restaurant_order_items',
        sa.Column('id',         sa.String(36),        primary_key=True),
        sa.Column('order_id',   sa.String(36),        nullable=False),
        sa.Column('product_id', sa.String(36),        nullable=False),
        sa.Column('quantity',   sa.Numeric(10, 2),    nullable=False, server_default='1'),
        sa.Column('unit_price', sa.Numeric(10, 2),    nullable=False),
        sa.Column('notes',      sa.String(255),       nullable=True),
        sa.Column('status',     sa.Enum('pending', 'preparing', 'ready',
                                        name='restaurant_item_status'),
                  nullable=False, server_default='pending'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    op.create_index('ix_restaurant_order_items_order_id', 'restaurant_order_items', ['order_id'])
    op.create_foreign_key('fk_ritems_order',   'restaurant_order_items', 'restaurant_orders', ['order_id'],   ['id'], ondelete='CASCADE')
    op.create_foreign_key('fk_ritems_product', 'restaurant_order_items', 'products',          ['product_id'], ['id'], ondelete='RESTRICT')


def downgrade():
    op.drop_constraint('fk_ritems_product', 'restaurant_order_items', type_='foreignkey')
    op.drop_constraint('fk_ritems_order',   'restaurant_order_items', type_='foreignkey')
    op.drop_index('ix_restaurant_order_items_order_id', 'restaurant_order_items')
    op.drop_table('restaurant_order_items')

    op.drop_constraint('fk_rorders_sale',      'restaurant_orders', type_='foreignkey')
    op.drop_constraint('fk_rorders_table',     'restaurant_orders', type_='foreignkey')
    op.drop_constraint('fk_rorders_warehouse', 'restaurant_orders', type_='foreignkey')
    op.drop_constraint('fk_rorders_tenant',    'restaurant_orders', type_='foreignkey')
    op.drop_index('ix_restaurant_orders_table_id',     'restaurant_orders')
    op.drop_index('ix_restaurant_orders_warehouse_id', 'restaurant_orders')
    op.drop_index('ix_restaurant_orders_tenant_id',    'restaurant_orders')
    op.drop_table('restaurant_orders')

    op.drop_constraint('fk_rtables_warehouse', 'restaurant_tables', type_='foreignkey')
    op.drop_constraint('fk_rtables_tenant',    'restaurant_tables', type_='foreignkey')
    op.drop_index('ix_restaurant_tables_warehouse_id', 'restaurant_tables')
    op.drop_index('ix_restaurant_tables_tenant_id',    'restaurant_tables')
    op.drop_table('restaurant_tables')

    op.execute("DROP TYPE IF EXISTS restaurant_table_status")
    op.execute("DROP TYPE IF EXISTS restaurant_order_status")
    op.execute("DROP TYPE IF EXISTS restaurant_item_status")
