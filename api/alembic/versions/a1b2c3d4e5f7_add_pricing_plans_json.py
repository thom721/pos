"""add pricing_plans_json to platform_config

Revision ID: a1b2c3d4e5f7
Revises: z0a1b2c3d4e5
Create Date: 2026-07-22 00:00:00.000000
"""
from typing import Sequence, Union
import sqlalchemy as sa
from alembic import op

revision: str = 'a1b2c3d4e5f7'
down_revision: Union[str, None] = 'z0a1b2c3d4e5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE platform_config "
        "ADD COLUMN IF NOT EXISTS pricing_plans_json TEXT NULL DEFAULT NULL"
    )


def downgrade() -> None:
    try:
        op.drop_column('platform_config', 'pricing_plans_json')
    except Exception:
        pass
