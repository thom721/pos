"""app_config: ajouter warehouse_id pour config par depot

Revision ID: o9p0q1r2s3t4
Revises: n8o9p0q1r2s3
Create Date: 2026-07-18
"""
from alembic import op
import sqlalchemy as sa

revision = 'o9p0q1r2s3t4'
down_revision = 'n8o9p0q1r2s3'
branch_labels = None
depends_on = None


def upgrade():
    # Colonne sans index=True pour éviter le double index avec create_index
    op.add_column('app_config',
        sa.Column('warehouse_id', sa.String(36), nullable=True)
    )
    # FK séparée (plus robuste sur MySQL)
    op.create_foreign_key(
        'fk_app_config_warehouse_id',
        'app_config', 'warehouses',
        ['warehouse_id'], ['id'],
        ondelete='SET NULL',
    )
    op.create_index('ix_app_config_warehouse_id', 'app_config', ['warehouse_id'])

    # Data migration: associer les rows existants au dépôt par défaut du tenant
    bind = op.get_bind()
    bind.execute(sa.text("""
        UPDATE app_config ac
        JOIN warehouses w ON w.tenant_id = ac.tenant_id AND w.is_default = 1
        SET ac.warehouse_id = w.id
        WHERE ac.warehouse_id IS NULL AND ac.tenant_id IS NOT NULL
    """))


def downgrade():
    op.drop_constraint('fk_app_config_warehouse_id', 'app_config', type_='foreignkey')
    op.drop_index('ix_app_config_warehouse_id', 'app_config')
    op.drop_column('app_config', 'warehouse_id')
