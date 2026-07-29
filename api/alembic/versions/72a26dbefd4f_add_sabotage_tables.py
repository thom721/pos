"""add sabotage tables

Revision ID: 72a26dbefd4f
Revises: 12ca78b0616a
Create Date: 2026-07-29 11:52:57.025265

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '72a26dbefd4f'
down_revision: Union[str, Sequence[str], None] = '12ca78b0616a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'clients_sabotage',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.Column('tenant_id', sa.String(length=36), sa.ForeignKey('tenants.id'), nullable=True, index=True),
        sa.Column('warehouse_id', sa.String(length=36), sa.ForeignKey('warehouses.id'), nullable=True, index=True),
        sa.Column('nom', sa.String(length=255), nullable=False),
        sa.Column('prenom', sa.String(length=255), nullable=False),
        sa.Column('telephone', sa.String(length=50), nullable=False),
        sa.Column('adresse', sa.Text(), nullable=False),
        sa.Column('account_number', sa.String(length=6), nullable=False),
        sa.Column('extra_fields', sa.Text(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.UniqueConstraint('tenant_id', 'account_number', name='uq_client_sabotage_tenant_account'),
        sa.UniqueConstraint('tenant_id', 'telephone', name='uq_client_sabotage_tenant_telephone'),
    )

    op.create_table(
        'depots_sabotage',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.Column('tenant_id', sa.String(length=36), sa.ForeignKey('tenants.id'), nullable=True, index=True),
        sa.Column('warehouse_id', sa.String(length=36), sa.ForeignKey('warehouses.id'), nullable=True, index=True),
        sa.Column('client_id', sa.String(length=36), sa.ForeignKey('clients_sabotage.id'), nullable=False, index=True),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('amount', sa.Numeric(12, 2), nullable=False),
        sa.Column('note', sa.Text(), nullable=True),
    )

    op.create_table(
        'retraits_sabotage',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.Column('tenant_id', sa.String(length=36), sa.ForeignKey('tenants.id'), nullable=True, index=True),
        sa.Column('warehouse_id', sa.String(length=36), sa.ForeignKey('warehouses.id'), nullable=True, index=True),
        sa.Column('client_id', sa.String(length=36), sa.ForeignKey('clients_sabotage.id'), nullable=False, index=True),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('amount', sa.Numeric(12, 2), nullable=False),
        sa.Column('note', sa.Text(), nullable=True),
    )

    with op.batch_alter_table('app_config', schema=None) as batch_op:
        batch_op.add_column(sa.Column('client_sabotage_fields', sa.Text(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('app_config', schema=None) as batch_op:
        batch_op.drop_column('client_sabotage_fields')

    op.drop_table('retraits_sabotage')
    op.drop_table('depots_sabotage')
    op.drop_table('clients_sabotage')
