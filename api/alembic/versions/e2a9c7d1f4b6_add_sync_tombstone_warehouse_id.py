"""add warehouse_id to sync_tombstones

Revision ID: e2a9c7d1f4b6
Revises: d8f1a4c6e9b3
Create Date: 2026-11-01

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'e2a9c7d1f4b6'
down_revision: Union[str, Sequence[str], None] = 'd8f1a4c6e9b3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, col: str) -> bool:
    bind = op.get_bind()
    cols = [c['name'] for c in _inspect(bind).get_columns(table)]
    return col in cols


def upgrade() -> None:
    if not _col_exists('sync_tombstones', 'warehouse_id'):
        op.add_column('sync_tombstones',
                       sa.Column('warehouse_id', sa.String(length=36), nullable=True))
        op.create_index('ix_sync_tombstones_warehouse_id', 'sync_tombstones', ['warehouse_id'])


def downgrade() -> None:
    if _col_exists('sync_tombstones', 'warehouse_id'):
        op.drop_index('ix_sync_tombstones_warehouse_id', table_name='sync_tombstones')
        op.drop_column('sync_tombstones', 'warehouse_id')
