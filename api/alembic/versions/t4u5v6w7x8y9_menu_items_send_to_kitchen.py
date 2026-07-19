"""menu_items: ajout send_to_kitchen (bool, défaut True)

Revision ID: t4u5v6w7x8y9
Revises: s3t4u5v6w7x8
Create Date: 2026-07-19
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 't4u5v6w7x8y9'
down_revision: Union[str, None] = 's3t4u5v6w7x8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
    if not _col_exists('menu_items', 'send_to_kitchen'):
        op.add_column('menu_items',
            sa.Column('send_to_kitchen', sa.Boolean(),
                      nullable=False, server_default='1'))


def downgrade() -> None:
    if _col_exists('menu_items', 'send_to_kitchen'):
        op.drop_column('menu_items', 'send_to_kitchen')
