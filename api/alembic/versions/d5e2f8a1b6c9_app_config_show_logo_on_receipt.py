"""app_config show_logo_on_receipt

Revision ID: d5e2f8a1b6c9
Revises: c4d7e1f9a2b3
Create Date: 2026-09-14 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd5e2f8a1b6c9'
down_revision: Union[str, Sequence[str], None] = 'c4d7e1f9a2b3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table("app_config") as batch_op:
        batch_op.add_column(
            sa.Column("show_logo_on_receipt", sa.Boolean(), nullable=False, server_default=sa.true())
        )


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table("app_config") as batch_op:
        batch_op.drop_column("show_logo_on_receipt")
