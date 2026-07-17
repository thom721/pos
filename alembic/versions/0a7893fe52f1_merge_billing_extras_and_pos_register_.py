"""merge_billing_extras_and_pos_register_session

Revision ID: 0a7893fe52f1
Revises: b1c2d3e4f5a6, p1q2r3s4t5u6
Create Date: 2026-07-17 19:44:24.526790

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0a7893fe52f1'
down_revision: Union[str, Sequence[str], None] = ('b1c2d3e4f5a6', 'p1q2r3s4t5u6')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
