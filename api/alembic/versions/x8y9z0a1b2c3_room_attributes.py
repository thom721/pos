"""room_attributes table for hotel room characteristics

Revision ID: x8y9z0a1b2c3
Revises: w7x8y9z0a1b2
Create Date: 2026-07-20
"""
from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = 'x8y9z0a1b2c3'
down_revision: Union[str, None] = 'w7x8y9z0a1b2'
branch_labels = None
depends_on = None


def _table_exists(name: str) -> bool:
    bind = op.get_bind()
    return sa.inspect(bind).has_table(name)


def upgrade() -> None:
    if _table_exists('room_attributes'):
        return
    op.create_table(
        'room_attributes',
        sa.Column('id',         sa.String(36),  primary_key=True),
        sa.Column('tenant_id',  sa.String(36),  sa.ForeignKey('tenants.id'),          nullable=False, index=True),
        sa.Column('table_id',   sa.String(36),  sa.ForeignKey('restaurant_tables.id'), nullable=False, index=True),
        sa.Column('key',        sa.String(100), nullable=False),
        sa.Column('value',      sa.String(255), nullable=False, server_default=''),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
    )


def downgrade() -> None:
    op.drop_table('room_attributes')
