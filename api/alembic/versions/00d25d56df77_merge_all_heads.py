"""merge all heads

Revision ID: 00d25d56df77
Revises: 7b8f4a0c2f11, 9d52902ed421, a0b1c2d3e4f5, a3d4e5f6g7h8, a2b1c4d3e6f5, b2c3d4e5f6a7, b3c4d5e6f7a8, c4d5e6f7g8h9, f3930ab198e9, s5t6u7v8w9x0, i9j0k1l2m3n4
Create Date: 2026-07-26 19:09:08.359493

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '00d25d56df77'
down_revision: Union[str, Sequence[str], None] = ('7b8f4a0c2f11', '9d52902ed421', 'a0b1c2d3e4f5', 'a3d4e5f6g7h8', 'a2b1c4d3e6f5', 'b2c3d4e5f6a7', 'b3c4d5e6f7a8', 'c4d5e6f7g8h9', 'f3930ab198e9', 's5t6u7v8w9x0', 'i9j0k1l2m3n4')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
