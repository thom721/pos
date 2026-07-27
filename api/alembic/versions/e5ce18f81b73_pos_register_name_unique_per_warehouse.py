"""pos register name unique per warehouse

Revision ID: e5ce18f81b73
Revises: 3595ff6af7a2
Create Date: 2026-07-27 09:48:41.917605

"""
from typing import Sequence, Union

from alembic import op
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = 'e5ce18f81b73'
down_revision: Union[str, Sequence[str], None] = '3595ff6af7a2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema.

    Une caisse (pos_register) ne peut pas avoir le même nom qu'une autre
    caisse du même dépôt (warehouse_id). Deux dépôts différents peuvent
    avoir chacun une caisse "Caisse 1".
    Best-effort : si des doublons existent déjà, la création de l'index
    échoue silencieusement (idempotent, cohérent avec 9d52902ed421).
    """
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        return  # SQLite (tests locaux) : mono-tenant, pas de collision possible

    inspector = _inspect(bind)
    if "pos_registers" not in inspector.get_table_names():
        return

    indexes = inspector.get_indexes("pos_registers")
    if any(idx["name"] == "uq_register_name_warehouse" for idx in indexes):
        return  # déjà migré

    try:
        op.create_index(
            "uq_register_name_warehouse", "pos_registers", ["name", "warehouse_id"], unique=True,
        )
    except Exception:
        pass  # doublons existants — à nettoyer manuellement avant de réessayer


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        return
    try:
        op.drop_index("uq_register_name_warehouse", table_name="pos_registers")
    except Exception:
        pass
