"""add price to restaurant_tables

Revision ID: z0a1b2c3d4e5
Revises: y9z0a1b2c3d4
Create Date: 2026-07-20 00:00:00.000000
"""
from typing import Sequence, Union
import sqlalchemy as sa
from alembic import op

revision: str = 'z0a1b2c3d4e5'
down_revision: Union[str, None] = 'y9z0a1b2c3d4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE restaurant_tables "
        "ADD COLUMN IF NOT EXISTS price DECIMAL(12,2) NULL DEFAULT 0"
    )


def downgrade() -> None:
    op.drop_column('restaurant_tables', 'price')
