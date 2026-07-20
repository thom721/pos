"""add price_per_day and price_per_moment to restaurant_tables

Revision ID: a1b2c3d4e5f6
Revises: z0a1b2c3d4e5
Create Date: 2026-07-20
"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'z0a1b2c3d4e5'
branch_labels = None
depends_on = None


def _col_exists(table: str, column: str) -> bool:
    bind = op.get_bind()
    cols = [c['name'] for c in sa.inspect(bind).get_columns(table)]
    return column in cols


def upgrade() -> None:
    if not _col_exists('restaurant_tables', 'price_per_day'):
        op.add_column('restaurant_tables',
            sa.Column('price_per_day', sa.Numeric(12, 2), nullable=True, server_default='0'))
    if not _col_exists('restaurant_tables', 'price_per_moment'):
        op.add_column('restaurant_tables',
            sa.Column('price_per_moment', sa.Numeric(12, 2), nullable=True, server_default='0'))


def downgrade() -> None:
    op.drop_column('restaurant_tables', 'price_per_moment')
    op.drop_column('restaurant_tables', 'price_per_day')
