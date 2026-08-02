"""pos register device approval

Revision ID: b91881b6710b
Revises: 9124d8ef3996
Create Date: 2026-08-02 14:21:28.466534

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b91881b6710b'
down_revision: Union[str, Sequence[str], None] = '9124d8ef3996'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table('pos_registers') as batch_op:
        batch_op.add_column(sa.Column('is_device_approved', sa.Boolean(), nullable=False, server_default=sa.true()))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('pos_registers') as batch_op:
        batch_op.drop_column('is_device_approved')
