"""warehouse.is_claimed — marque un dépôt comme utilisé par une installation

Revision ID: l6m7n8o9p0q1
Revises: k6l7m8n9o0p1
Create Date: 2026-07-16
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'l6m7n8o9p0q1'
down_revision: Union[str, None] = 'k6l7m8n9o0p1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
    if not _col_exists('warehouses', 'is_claimed'):
        op.add_column('warehouses',
            sa.Column('is_claimed', sa.Boolean(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('warehouses', 'is_claimed')
