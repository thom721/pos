"""fix_register_date_columns_text

Revision ID: f8bf3dfe3543
Revises: 00d25d56df77
Create Date: 2026-07-26 19:22:17.547848

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f8bf3dfe3543'
down_revision: Union[str, Sequence[str], None] = '00d25d56df77'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


_COLS = ('trial_ends_at', 'subscription_started_at', 'subscription_ends_at')


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != 'mysql':
        return
    for col in _COLS:
        bind.execute(sa.text(f"ALTER TABLE pos_registers MODIFY COLUMN {col} TEXT(600)"))


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != 'mysql':
        return
    for col in _COLS:
        bind.execute(sa.text(f"ALTER TABLE pos_registers MODIFY COLUMN {col} DATETIME"))
