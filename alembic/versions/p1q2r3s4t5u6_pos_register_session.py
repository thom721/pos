"""add session_token and last_seen to pos_registers; add default warehouse+register at registration

Revision ID: p1q2r3s4t5u6
Revises: n8o9p0q1r2s3
Create Date: 2026-07-17 00:00:00.000000
"""
from typing import Sequence, Union
import sqlalchemy as sa
from alembic import op

revision: str = 'p1q2r3s4t5u6'
down_revision: Union[str, Sequence[str], None] = 'n8o9p0q1r2s3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    try:
        op.add_column('pos_registers',
            sa.Column('session_token', sa.String(36), nullable=True))
    except Exception:
        pass
    try:
        op.add_column('pos_registers',
            sa.Column('last_seen', sa.DateTime(timezone=True), nullable=True))
    except Exception:
        pass


def downgrade() -> None:
    op.drop_column('pos_registers', 'last_seen')
    op.drop_column('pos_registers', 'session_token')
