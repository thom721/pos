"""warehouse name unique per tenant

Revision ID: 3595ff6af7a2
Revises: b684dc146574
Create Date: 2026-07-27 09:45:53.005162

"""
from typing import Sequence, Union

from alembic import op
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = '3595ff6af7a2'
down_revision: Union[str, Sequence[str], None] = 'b684dc146574'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema.

    Un tenant ne peut pas avoir deux business (dépôts) du même nom.
    Best-effort : si des doublons existent déjà en base, la création de
    l'index échoue silencieusement (idempotent, cohérent avec 9d52902ed421).
    """
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        return  # SQLite (tests locaux) : mono-tenant, pas de collision possible

    inspector = _inspect(bind)
    if "warehouses" not in inspector.get_table_names():
        return

    indexes = inspector.get_indexes("warehouses")
    if any(idx["name"] == "uq_warehouse_name_tenant" for idx in indexes):
        return  # déjà migré

    try:
        op.create_index(
            "uq_warehouse_name_tenant", "warehouses", ["name", "tenant_id"], unique=True,
        )
    except Exception:
        pass  # doublons existants — à nettoyer manuellement avant de réessayer


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        return
    try:
        op.drop_index("uq_warehouse_name_tenant", table_name="warehouses")
    except Exception:
        pass
