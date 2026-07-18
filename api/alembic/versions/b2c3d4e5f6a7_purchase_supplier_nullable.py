"""purchase_supplier_nullable — rend supplier_id optionnel dans purchases

Revision ID: b2c3d4e5f6a7
Revises: f1a2b3c4d5e6
Create Date: 2026-07-18 00:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'b2c3d4e5f6a7'
down_revision: Union[str, None] = 'f1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(sa.text(
        "ALTER TABLE purchases MODIFY COLUMN supplier_id VARCHAR(36) NULL"
    ))


def downgrade() -> None:
    # Remettre NOT NULL seulement si toutes les lignes ont un supplier_id
    op.execute(sa.text(
        "UPDATE purchases SET supplier_id = '00000000-0000-0000-0000-000000000000' WHERE supplier_id IS NULL"
    ))
    op.execute(sa.text(
        "ALTER TABLE purchases MODIFY COLUMN supplier_id VARCHAR(36) NOT NULL"
    ))
