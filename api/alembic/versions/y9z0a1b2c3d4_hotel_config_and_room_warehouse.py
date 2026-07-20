"""hotel_checkin_fields in app_config; warehouse_id in room_attributes

Revision ID: y9z0a1b2c3d4
Revises: x8y9z0a1b2c3
Create Date: 2026-07-20
"""
from typing import Union
from alembic import op
import sqlalchemy as sa


revision: str = 'y9z0a1b2c3d4'
down_revision: Union[str, None] = 'x8y9z0a1b2c3'
branch_labels = None
depends_on = None


def _col_exists(table: str, column: str) -> bool:
    bind = op.get_bind()
    cols = [c['name'] for c in sa.inspect(bind).get_columns(table)]
    return column in cols


def upgrade() -> None:
    if not _col_exists('app_config', 'hotel_checkin_fields'):
        op.add_column('app_config',
            sa.Column('hotel_checkin_fields', sa.Text(), nullable=True))

    if not _col_exists('room_attributes', 'warehouse_id'):
        op.add_column('room_attributes',
            sa.Column('warehouse_id', sa.String(36),
                      sa.ForeignKey('warehouses.id'), nullable=True, index=True))


def downgrade() -> None:
    op.drop_column('room_attributes', 'warehouse_id')
    op.drop_column('app_config', 'hotel_checkin_fields')
