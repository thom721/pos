"""add product_ids to discounts

Revision ID: 8fa9aca853ef
Revises: acac0d9c1008
Create Date: 2026-07-28 20:40:10.461070

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '8fa9aca853ef'
down_revision: Union[str, Sequence[str], None] = 'acac0d9c1008'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()
    cols = {c["name"] for c in sa.inspect(bind).get_columns("discounts")}
    if "product_ids" not in cols:
        op.add_column("discounts", sa.Column("product_ids", sa.JSON(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    cols = {c["name"] for c in sa.inspect(bind).get_columns("discounts")}
    if "product_ids" in cols:
        op.drop_column("discounts", "product_ids")
