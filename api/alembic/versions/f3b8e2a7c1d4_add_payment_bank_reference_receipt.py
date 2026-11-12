"""add bank_reference and receipt_url to payments

Revision ID: f3b8e2a7c1d4
Revises: e2a9c7d1f4b6
Create Date: 2026-11-13

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'f3b8e2a7c1d4'
down_revision: Union[str, Sequence[str], None] = 'e2a9c7d1f4b6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, col: str) -> bool:
    bind = op.get_bind()
    cols = [c['name'] for c in _inspect(bind).get_columns(table)]
    return col in cols


def upgrade() -> None:
    if not _col_exists('payments', 'bank_reference'):
        op.add_column('payments', sa.Column('bank_reference', sa.String(length=100), nullable=True))
    if not _col_exists('payments', 'receipt_url'):
        op.add_column('payments', sa.Column('receipt_url', sa.String(length=255), nullable=True))


def downgrade() -> None:
    if _col_exists('payments', 'receipt_url'):
        op.drop_column('payments', 'receipt_url')
    if _col_exists('payments', 'bank_reference'):
        op.drop_column('payments', 'bank_reference')
