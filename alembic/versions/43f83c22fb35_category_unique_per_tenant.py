"""category_unique_per_tenant

Revision ID: 43f83c22fb35
Revises: q2r3s4t5u6v7
Create Date: 2026-07-18 06:56:31.412089

Replace global unique index on Category.name with a per-tenant composite
unique constraint (tenant_id, name) so different tenants can share the same
category names.
"""
from typing import Sequence, Union
from alembic import op

revision: str = '43f83c22fb35'
down_revision: Union[str, Sequence[str], None] = 'q2r3s4t5u6v7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Drop the old global unique index on name
    try:
        op.drop_index('name', table_name='categories')
    except Exception:
        pass  # may already be gone

    # Add composite unique constraint per tenant
    try:
        op.create_unique_constraint(
            'uq_category_tenant_name', 'categories', ['tenant_id', 'name']
        )
    except Exception:
        pass  # already exists


def downgrade() -> None:
    try:
        op.drop_constraint('uq_category_tenant_name', 'categories', type_='unique')
    except Exception:
        pass
    try:
        op.create_index('name', 'categories', ['name'], unique=True)
    except Exception:
        pass
