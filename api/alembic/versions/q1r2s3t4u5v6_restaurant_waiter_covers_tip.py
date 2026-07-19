"""restaurant: waiter_id sur table, covers et tip sur commande

Revision ID: q1r2s3t4u5v6
Revises: p0q1r2s3t4u5
Create Date: 2026-07-18
"""
from alembic import op
import sqlalchemy as sa

revision = 'q1r2s3t4u5v6'
down_revision = 'p0q1r2s3t4u5'
branch_labels = None
depends_on = None


def upgrade():
    # Serveur assigné à la table
    op.add_column('restaurant_tables',
        sa.Column('waiter_id', sa.String(36), nullable=True))
    op.create_index('ix_restaurant_tables_waiter_id', 'restaurant_tables', ['waiter_id'])
    op.create_foreign_key('fk_rtables_waiter', 'restaurant_tables', 'users',
        ['waiter_id'], ['id'], ondelete='SET NULL')

    # Nombre de couverts et pourboire sur la commande
    op.add_column('restaurant_orders',
        sa.Column('covers', sa.Integer, nullable=False, server_default='1'))
    op.add_column('restaurant_orders',
        sa.Column('tip', sa.Numeric(10, 2), nullable=False, server_default='0'))


def downgrade():
    op.drop_column('restaurant_orders', 'tip')
    op.drop_column('restaurant_orders', 'covers')

    op.drop_constraint('fk_rtables_waiter', 'restaurant_tables', type_='foreignkey')
    op.drop_index('ix_restaurant_tables_waiter_id', 'restaurant_tables')
    op.drop_column('restaurant_tables', 'waiter_id')
