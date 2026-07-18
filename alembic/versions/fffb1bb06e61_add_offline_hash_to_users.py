"""add_offline_hash_to_users

Revision ID: fffb1bb06e61
Revises: 6b68da5b46ff
Create Date: 2026-07-18 08:23:13.247505

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision: str = 'fffb1bb06e61'
down_revision: Union[str, Sequence[str], None] = '6b68da5b46ff'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('offline_hash', sa.String(length=64), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'offline_hash')
