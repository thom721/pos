"""sale customer loyalty balance snapshot

Revision ID: 56af530eb614
Revises: 81f87741e746
Create Date: 2026-08-01 17:11:22.697528

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '56af530eb614'
down_revision: Union[str, Sequence[str], None] = '81f87741e746'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table('sales') as batch_op:
        batch_op.add_column(sa.Column('customer_loyalty_balance', sa.Numeric(12, 2), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('sales') as batch_op:
        batch_op.drop_column('customer_loyalty_balance')
