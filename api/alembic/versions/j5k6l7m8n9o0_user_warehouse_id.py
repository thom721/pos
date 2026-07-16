"""user_warehouse_id -- assigner un depot a un utilisateur (nullable)

Revision ID: j5k6l7m8n9o0
Revises: i4j5k6l7m8n9
Create Date: 2026-07-16
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'j5k6l7m8n9o0'
down_revision: Union[str, None] = 'i4j5k6l7m8n9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
    if not _col_exists('users', 'warehouse_id'):
        op.add_column('users',
            sa.Column('warehouse_id', sa.String(36), nullable=True))
        op.create_foreign_key(
            'fk_user_warehouse', 'users', 'warehouses',
            ['warehouse_id'], ['id'])
        op.create_index('ix_user_warehouse_id', 'users', ['warehouse_id'])


def downgrade() -> None:
    op.drop_index('ix_user_warehouse_id', table_name='users')
    op.drop_constraint('fk_user_warehouse', 'users', type_='foreignkey')
    op.drop_column('users', 'warehouse_id')
