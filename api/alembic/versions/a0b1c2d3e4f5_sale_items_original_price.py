"""sale_items: ajout colonne original_price (prix catalogue avant remise article)

Revision ID: a0b1c2d3e4f5
Revises: z0a1b2c3d4e5
Create Date: 2026-07-25
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = 'a0b1c2d3e4f5'
down_revision: Union[str, None] = 'z0a1b2c3d4e5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    bind = op.get_bind()
    if bind.dialect.name == 'sqlite':
        rows = bind.execute(sa.text(f"PRAGMA table_info({table})")).fetchall()
        return any(row[1] == column for row in rows)
    n = bind.execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
    if not _col_exists('sale_items', 'original_price'):
        op.add_column('sale_items',
            sa.Column('original_price', sa.Numeric(12, 2), nullable=True))


def downgrade() -> None:
    if _col_exists('sale_items', 'original_price'):
        op.drop_column('sale_items', 'original_price')
