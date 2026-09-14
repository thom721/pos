"""app_config unique constraint on (tenant_id, warehouse_id)

Revision ID: c4d7e1f9a2b3
Revises: 879144fa7bfc
Create Date: 2026-09-14 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c4d7e1f9a2b3'
down_revision: Union[str, Sequence[str], None] = '879144fa7bfc'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    conn = op.get_bind()
    # get_or_create() (api/services/config_service.py) ne devrait jamais créer
    # deux lignes pour le même (tenant_id, warehouse_id), mais rien au niveau
    # DB ne l'empêchait avant cette contrainte. On dédoublonne d'abord en
    # gardant la ligne la plus ancienne, sinon l'ALTER TABLE échoue.
    conn.execute(sa.text("""
        DELETE ac1 FROM app_config ac1
        INNER JOIN app_config ac2
          ON ac1.tenant_id = ac2.tenant_id
         AND ac1.warehouse_id = ac2.warehouse_id
         AND ac1.warehouse_id IS NOT NULL
         AND (ac1.created_at > ac2.created_at
              OR (ac1.created_at = ac2.created_at AND ac1.id > ac2.id))
    """))
    op.create_unique_constraint(
        'uq_app_config_tenant_warehouse', 'app_config', ['tenant_id', 'warehouse_id']
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint('uq_app_config_tenant_warehouse', 'app_config', type_='unique')
