"""fix sale_item tenant_id null — copie depuis sale parent

Revision ID: a1c2d3e4f5g6
Revises: a1b2c3d4e5f6
Create Date: 2026-07-25 00:00:00.000000
"""
from typing import Sequence, Union
from alembic import op

revision: str = 'a1c2d3e4f5g6'
down_revision: Union[str, None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Les SaleItem créés via l'API directe (mobile→cloud) avaient tenant_id=NULL
    # parce que create_sale() ne le propagait pas aux items.
    # Cette migration copie tenant_id du parent sale vers chaque item orphelin.
    op.execute("""
        UPDATE sale_items si
        JOIN sales s ON si.sale_id = s.id
        SET si.tenant_id = s.tenant_id
        WHERE si.tenant_id IS NULL
          AND s.tenant_id IS NOT NULL
    """)


def downgrade() -> None:
    pass
