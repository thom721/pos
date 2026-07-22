"""add pricing_plans_json to platform_config

Revision ID: r3s4t5u6v7w8
Revises: q2r3s4t5u6v7
Create Date: 2026-07-22 00:00:00.000000
"""
from typing import Sequence, Union
import sqlalchemy as sa
from alembic import op

revision: str = 'r3s4t5u6v7w8'
down_revision: Union[str, Sequence[str], None] = 'q2r3s4t5u6v7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    try:
        op.add_column('platform_config',
            sa.Column('pricing_plans_json', sa.Text(), nullable=True, default=None))
    except Exception:
        pass


def downgrade() -> None:
    try:
        op.drop_column('platform_config', 'pricing_plans_json')
    except Exception:
        pass
