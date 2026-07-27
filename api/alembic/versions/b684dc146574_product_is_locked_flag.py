"""product is_locked flag

Revision ID: b684dc146574
Revises: e71f2581cf2d
Create Date: 2026-07-27 09:45:48.984485

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b684dc146574'
down_revision: Union[str, Sequence[str], None] = 'e71f2581cf2d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table('products') as batch:
        batch.add_column(sa.Column(
            'is_locked',
            sa.Boolean(),
            nullable=False,
            server_default=sa.text('0'),
        ))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('products') as batch:
        batch.drop_column('is_locked')
