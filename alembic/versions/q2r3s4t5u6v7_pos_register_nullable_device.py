"""make pos_registers.device_id nullable (slot model)

Revision ID: q2r3s4t5u6v7
Revises: 0a7893fe52f1
Create Date: 2026-07-17 00:00:00.000000
"""
from typing import Sequence, Union
import sqlalchemy as sa
from alembic import op

revision: str = 'q2r3s4t5u6v7'
down_revision: Union[str, Sequence[str], None] = '0a7893fe52f1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    try:
        op.drop_constraint('uq_register_tenant_device', 'pos_registers', type_='unique')
    except Exception:
        pass
    try:
        op.alter_column('pos_registers', 'device_id',
                        existing_type=sa.String(36),
                        nullable=True)
    except Exception:
        pass
    try:
        op.create_unique_constraint('uq_register_tenant_device', 'pos_registers',
                                    ['tenant_id', 'device_id'])
    except Exception:
        pass


def downgrade() -> None:
    op.drop_constraint('uq_register_tenant_device', 'pos_registers', type_='unique')
    op.alter_column('pos_registers', 'device_id',
                    existing_type=sa.String(36),
                    nullable=False)
    op.create_unique_constraint('uq_register_tenant_device', 'pos_registers',
                                ['tenant_id', 'device_id'])
