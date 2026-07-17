"""add_billing_extras_table

Revision ID: b1c2d3e4f5a6
Revises: fd860b506c43
Create Date: 2026-07-17 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b1c2d3e4f5a6'
down_revision: Union[str, Sequence[str], None] = 'n8o9p0q1r2s3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'billing_extras',
        sa.Column('id',            sa.String(36),  nullable=False, primary_key=True),
        sa.Column('created_at',    sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at',    sa.DateTime(timezone=True), nullable=False),
        sa.Column('tenant_id',     sa.String(36),  nullable=False),
        sa.Column('resource_type', sa.String(20),  nullable=False),
        sa.Column('resource_id',   sa.String(36),  nullable=True),
        sa.Column('started_at',    sa.DateTime(timezone=True), nullable=False),
        sa.Column('ended_at',      sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id']),
    )
    op.create_index('ix_billing_extras_tenant_id', 'billing_extras', ['tenant_id'])


def downgrade() -> None:
    op.drop_index('ix_billing_extras_tenant_id', table_name='billing_extras')
    op.drop_table('billing_extras')
