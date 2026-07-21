"""restaurant_order_items: ajout label pour articles libres (hôtel)

Revision ID: a1b2c3d4e5f6
Revises: z0a1b2c3d4e5
Create Date: 2026-07-21
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
    if not _col_exists('restaurant_order_items', 'label'):
        op.add_column('restaurant_order_items',
            sa.Column('label', sa.String(255), nullable=True))
    # Ensure hotel price columns exist on restaurant_tables
    for col, type_ in [('price_per_day', sa.Numeric(12, 2)), ('price_per_moment', sa.Numeric(12, 2))]:
        if not _col_exists('restaurant_tables', col):
            op.add_column('restaurant_tables',
                sa.Column(col, type_, nullable=True, server_default='0'))


def downgrade() -> None:
    op.drop_column('restaurant_order_items', 'label')
