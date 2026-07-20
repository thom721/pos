"""add price to restaurant_tables

Revision ID: r3s4t5u6v7w8
Revises: fffb1bb06e61
Create Date: 2026-07-20 00:00:00.000000
"""
from typing import Sequence, Union
import sqlalchemy as sa
from alembic import op

revision: str = 'r3s4t5u6v7w8'
down_revision: Union[str, None] = 'fffb1bb06e61'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('restaurant_tables',
        sa.Column('price', sa.Numeric(12, 2), nullable=True, server_default='0')
    )


def downgrade() -> None:
    op.drop_column('restaurant_tables', 'price')
