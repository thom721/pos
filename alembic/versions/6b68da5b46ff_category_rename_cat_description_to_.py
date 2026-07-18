"""category_rename_cat_description_to_description

Revision ID: 6b68da5b46ff
Revises: 43f83c22fb35
Create Date: 2026-07-18 07:06:03.500271

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6b68da5b46ff'
down_revision: Union[str, Sequence[str], None] = '43f83c22fb35'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    cols = {c['name'] for c in sa.inspect(bind).get_columns('categories')}
    if 'cat_description' in cols and 'description' not in cols:
        op.alter_column(
            'categories', 'cat_description',
            new_column_name='description',
            existing_type=sa.String(255),
            existing_nullable=True,
        )


def downgrade() -> None:
    op.alter_column(
        'categories', 'description',
        new_column_name='cat_description',
        existing_type=sa.String(255),
        existing_nullable=True,
    )
