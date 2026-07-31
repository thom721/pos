"""add warehouse is_entrepot

Revision ID: 1c91ed10a01d
Revises: 1f2c9fce5a4c
Create Date: 2026-07-31 15:55:02.045482

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '1c91ed10a01d'
down_revision: Union[str, Sequence[str], None] = '1f2c9fce5a4c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table("warehouses") as batch_op:
        batch_op.add_column(
            sa.Column("is_entrepot", sa.Boolean(), nullable=False, server_default="0")
        )


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table("warehouses") as batch_op:
        batch_op.drop_column("is_entrepot")
