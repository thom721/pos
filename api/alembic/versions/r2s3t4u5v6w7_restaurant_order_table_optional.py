"""restaurant_orders: table_id optionnel (comptoir/bar sans table)

Revision ID: r2s3t4u5v6w7
Revises: q1r2s3t4u5v6
Create Date: 2026-07-19
"""
from alembic import op
import sqlalchemy as sa

revision = 'r2s3t4u5v6w7'
down_revision = 'q1r2s3t4u5v6'
branch_labels = None
depends_on = None


def upgrade():
    # MySQL auto-names the FK; drop it by its actual name then recreate
    op.drop_constraint('restaurant_orders_ibfk_3', 'restaurant_orders', type_='foreignkey')
    op.alter_column('restaurant_orders', 'table_id',
                    existing_type=sa.String(36), nullable=True)
    op.create_foreign_key('restaurant_orders_ibfk_3', 'restaurant_orders', 'restaurant_tables',
                          ['table_id'], ['id'], ondelete='SET NULL')


def downgrade():
    op.drop_constraint('restaurant_orders_ibfk_3', 'restaurant_orders', type_='foreignkey')
    op.alter_column('restaurant_orders', 'table_id',
                    existing_type=sa.String(36), nullable=False)
    op.create_foreign_key('restaurant_orders_ibfk_3', 'restaurant_orders', 'restaurant_tables',
                          ['table_id'], ['id'], ondelete='CASCADE')
