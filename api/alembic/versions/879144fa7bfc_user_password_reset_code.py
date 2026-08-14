"""user password reset code

Revision ID: 879144fa7bfc
Revises: a1cb62855892
Create Date: 2026-08-13 20:07:27.459866

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '879144fa7bfc'
down_revision: Union[str, Sequence[str], None] = 'a1cb62855892'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table("users") as batch_op:
        batch_op.add_column(sa.Column("password_reset_code", sa.String(length=10), nullable=True))
        batch_op.add_column(sa.Column("password_reset_expires_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table("users") as batch_op:
        batch_op.drop_column("password_reset_expires_at")
        batch_op.drop_column("password_reset_code")
