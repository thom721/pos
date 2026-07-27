"""users_email_global_unique

Revision ID: 0615ee800806
Revises: f8bf3dfe3543
Create Date: 2026-07-26 20:08:39.063232

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0615ee800806'
down_revision: Union[str, Sequence[str], None] = 'f8bf3dfe3543'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    # Supprimer la contrainte composite (email, tenant_id) si elle existe
    if bind.dialect.name == 'mysql':
        try:
            op.drop_constraint('uq_user_email_tenant', 'users', type_='unique')
        except Exception:
            pass  # déjà absente ou jamais créée
    # Ajouter contrainte globale unique sur email (NULL autorisés — MySQL les ignore)
    op.create_unique_constraint('uq_user_email_global', 'users', ['email'])


def downgrade() -> None:
    op.drop_constraint('uq_user_email_global', 'users', type_='unique')
    op.create_unique_constraint('uq_user_email_tenant', 'users', ['email', 'tenant_id'])
