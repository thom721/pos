"""customer fname

Revision ID: 9124d8ef3996
Revises: 56af530eb614
Create Date: 2026-08-02 08:51:53.145718

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9124d8ef3996'
down_revision: Union[str, Sequence[str], None] = '56af530eb614'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table('customers') as batch_op:
        batch_op.add_column(sa.Column('fname', sa.String(255), nullable=True, server_default=''))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('customers') as batch_op:
        batch_op.drop_column('fname')
