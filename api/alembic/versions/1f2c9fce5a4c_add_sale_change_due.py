"""add sale change_due

Revision ID: 1f2c9fce5a4c
Revises: 0b5899cefeb3
Create Date: 2026-07-31 14:06:52.912711

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '1f2c9fce5a4c'
down_revision: Union[str, Sequence[str], None] = '0b5899cefeb3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table("sales") as batch_op:
        batch_op.add_column(
            sa.Column("change_due", sa.Numeric(12, 2), nullable=False, server_default="0")
        )


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table("sales") as batch_op:
        batch_op.drop_column("change_due")
