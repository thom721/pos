"""add housekeeping_tasks table

Revision ID: c4d5e6f7g8h9
Revises: c3d4e5f6g7h8
Down_revision: c3d4e5f6g7h8
Branch_labels: None
Depends_on: None
"""
from alembic import op
import sqlalchemy as sa


revision = 'c4d5e6f7g8h9'
down_revision = 'c3d4e5f6g7h8'
branch_labels = None
depends_on = None


def _table_exists(name: str) -> bool:
    bind = op.get_bind()
    result = bind.execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :n"
    ), {"n": name})
    return result.scalar() > 0


def upgrade():
    if _table_exists('housekeeping_tasks'):
        return
    op.create_table(
        'housekeeping_tasks',
        sa.Column('id', sa.String(36), nullable=False),
        sa.Column('tenant_id',    sa.String(36), sa.ForeignKey('tenants.id'),          nullable=False),
        sa.Column('warehouse_id', sa.String(36), sa.ForeignKey('warehouses.id'),        nullable=True),
        sa.Column('table_id',     sa.String(36), sa.ForeignKey('restaurant_tables.id'), nullable=False),
        sa.Column('description', sa.String(255), nullable=False),
        sa.Column(
            'status',
            sa.Enum('pending', 'done', name='housekeeping_task_status'),
            nullable=False,
            server_default='pending',
        ),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_housekeeping_tasks_tenant_id',    'housekeeping_tasks', ['tenant_id'])
    op.create_index('ix_housekeeping_tasks_warehouse_id', 'housekeeping_tasks', ['warehouse_id'])
    op.create_index('ix_housekeeping_tasks_table_id',     'housekeeping_tasks', ['table_id'])


def downgrade():
    op.drop_index('ix_housekeeping_tasks_table_id',     table_name='housekeeping_tasks')
    op.drop_index('ix_housekeeping_tasks_warehouse_id', table_name='housekeeping_tasks')
    op.drop_index('ix_housekeeping_tasks_tenant_id',    table_name='housekeeping_tasks')
    op.drop_table('housekeeping_tasks')
    op.execute("DROP TYPE IF EXISTS housekeeping_task_status")
