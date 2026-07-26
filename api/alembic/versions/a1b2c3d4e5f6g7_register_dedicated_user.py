"""add dedicated_user_id to pos_registers

Revision ID: a1b2c3d4e5f6g7
Revises: z0a1b2c3d4e5
Create Date: 2026-07-26 00:00:00.000000
"""
from typing import Sequence, Union
import sqlalchemy as sa
from alembic import op

revision: str = 'a1b2c3d4e5f6g7'
down_revision: Union[str, None] = 'z0a1b2c3d4e5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, col: str) -> bool:
    bind = op.get_bind()
    r = bind.execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": col})
    return r.scalar() > 0


def upgrade():
    if not _col_exists('pos_registers', 'dedicated_user_id'):
        op.add_column(
            'pos_registers',
            sa.Column('dedicated_user_id', sa.String(36),
                      sa.ForeignKey('users.id', ondelete='SET NULL'),
                      nullable=True, index=True),
        )


def downgrade():
    if _col_exists('pos_registers', 'dedicated_user_id'):
        op.drop_column('pos_registers', 'dedicated_user_id')
