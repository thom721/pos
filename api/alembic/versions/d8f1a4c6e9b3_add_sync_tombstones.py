"""add sync_tombstones table

Revision ID: d8f1a4c6e9b3
Revises: c3d6f9a2b5e8
Create Date: 2026-10-31

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'd8f1a4c6e9b3'
down_revision: Union[str, Sequence[str], None] = 'c3d6f9a2b5e8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    tables = _inspect(bind).get_table_names()
    if 'sync_tombstones' not in tables:
        op.create_table(
            'sync_tombstones',
            sa.Column('id', sa.String(length=36), primary_key=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.Column('tenant_id', sa.String(length=36), sa.ForeignKey('tenants.id'), nullable=True, index=True),
            sa.Column('entity_type', sa.String(length=50), nullable=False, index=True),
            sa.Column('record_id', sa.String(length=36), nullable=False, index=True),
            sa.UniqueConstraint('entity_type', 'record_id', name='uq_tombstone_entity_record'),
        )


def downgrade() -> None:
    bind = op.get_bind()
    tables = _inspect(bind).get_table_names()
    if 'sync_tombstones' in tables:
        op.drop_table('sync_tombstones')
