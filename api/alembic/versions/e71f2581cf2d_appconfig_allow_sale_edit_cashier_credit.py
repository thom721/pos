"""appconfig_allow_sale_edit_cashier_credit

Revision ID: e71f2581cf2d
Revises: 0615ee800806
Create Date: 2026-07-26 20:50:49.974826

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e71f2581cf2d'
down_revision: Union[str, Sequence[str], None] = '0615ee800806'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('app_config', sa.Column('allow_sale_edit',      sa.Boolean(), nullable=False, server_default='0'))
    op.add_column('app_config', sa.Column('allow_cashier_credit', sa.Boolean(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('app_config', 'allow_cashier_credit')
    op.drop_column('app_config', 'allow_sale_edit')
