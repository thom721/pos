"""entrepot address subscription multi and entrepot payments

Revision ID: d55f7b8bc650
Revises: b91881b6710b
Create Date: 2026-08-08 09:44:17.184724

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd55f7b8bc650'
down_revision: Union[str, Sequence[str], None] = 'b91881b6710b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table('warehouses') as batch:
        batch.add_column(sa.Column(
            'address',
            sa.String(255),
            nullable=True,
        ))
        batch.add_column(sa.Column(
            'subscription_ends_at',
            sa.Text(600),
            nullable=True,
        ))

    with op.batch_alter_table('billing_payments') as batch:
        batch.add_column(sa.Column(
            'entrepot_ids_json',
            sa.Text(),
            nullable=True,
        ))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('billing_payments') as batch:
        batch.drop_column('entrepot_ids_json')

    with op.batch_alter_table('warehouses') as batch:
        batch.drop_column('subscription_ends_at')
        batch.drop_column('address')
