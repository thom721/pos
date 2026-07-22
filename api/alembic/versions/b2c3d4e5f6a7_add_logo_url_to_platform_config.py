"""add logo_url to platform_config

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f7
Create Date: 2026-07-22
"""
from typing import Union
from alembic import op

revision: str = 'b2c3d4e5f6a7'
down_revision: Union[str, None] = 'a1b2c3d4e5f7'
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.execute(
        "ALTER TABLE platform_config "
        "ADD COLUMN IF NOT EXISTS logo_url VARCHAR(512) NULL DEFAULT NULL"
    )

def downgrade() -> None:
    op.execute("ALTER TABLE platform_config DROP COLUMN IF EXISTS logo_url")
