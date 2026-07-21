"""add housekeeping_tasks table

Revision ID: c3d4e5f6g7h8
Revises: a1b2c3d4e5f6
Down_revision: a1b2c3d4e5f6
Branch_labels: None
Depends_on: None
"""
from alembic import op
import sqlalchemy as sa


revision = 'c3d4e5f6g7h8'
down_revision = 'a1b2c3d4e5f6'
branch_labels = None
depends_on = None


def upgrade():
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
