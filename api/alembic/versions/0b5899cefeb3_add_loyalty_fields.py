"""add loyalty fields

Revision ID: 0b5899cefeb3
Revises: 72a26dbefd4f
Create Date: 2026-07-29 20:13:50.859282

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0b5899cefeb3'
down_revision: Union[str, Sequence[str], None] = '72a26dbefd4f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table('app_config', schema=None) as batch_op:
        batch_op.add_column(sa.Column('loyalty_enabled', sa.Boolean(), nullable=False, server_default='0'))
        batch_op.add_column(sa.Column('loyalty_percent', sa.Numeric(5, 2), nullable=False, server_default='0'))

    with op.batch_alter_table('customers', schema=None) as batch_op:
        batch_op.add_column(sa.Column('loyalty_balance', sa.Numeric(12, 2), nullable=False, server_default='0'))

    with op.batch_alter_table('sales', schema=None) as batch_op:
        batch_op.add_column(sa.Column('loyalty_earned', sa.Numeric(12, 2), nullable=False, server_default='0'))
        batch_op.add_column(sa.Column('loyalty_redeemed', sa.Numeric(12, 2), nullable=False, server_default='0'))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('sales', schema=None) as batch_op:
        batch_op.drop_column('loyalty_redeemed')
        batch_op.drop_column('loyalty_earned')

    with op.batch_alter_table('customers', schema=None) as batch_op:
        batch_op.drop_column('loyalty_balance')

    with op.batch_alter_table('app_config', schema=None) as batch_op:
        batch_op.drop_column('loyalty_percent')
        batch_op.drop_column('loyalty_enabled')
