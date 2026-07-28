"""fix sale status enum: uppercase values + cancelled member

Revision ID: 9b01df8bde55
Revises: 3d6ef4310920
Create Date: 2026-07-28 00:00:00.000000

Contexte : le modèle Python SaleStatus a longtemps eu des valeurs à la casse
incohérente (partial="partial" minuscule) et aucun membre "cancelled", alors
que sale_service.py écrit partout des littéraux "PAID"/"UNPAID"/"PARTIAL"/
"CANCELLED" (majuscules). Sur MySQL, la colonne native ENUM créée à l'origine
(via Base.metadata.create_all(), pas Alembic) n'autorise que
('unpaid','paid','partial','credit','pending') — "CANCELLED" n'y a jamais eu
sa place. Cette migration élargit l'ENUM natif pour accepter les valeurs
réellement écrites par l'application. No-op sur SQLite (pas d'ENUM natif).
"""
from typing import Sequence, Union

from alembic import op
from sqlalchemy.dialects import mysql


# revision identifiers, used by Alembic.
revision: str = '9b01df8bde55'
down_revision: Union[str, Sequence[str], None] = '3d6ef4310920'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


_OLD_ENUM = mysql.ENUM('unpaid', 'paid', 'partial', 'credit', 'pending')
_NEW_ENUM = mysql.ENUM('UNPAID', 'PAID', 'PARTIAL', 'CANCELLED', 'CREDIT', 'PENDING')


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        return  # SQLite : pas d'ENUM natif, aucune contrainte à élargir

    op.alter_column(
        'sales', 'status',
        existing_type=_OLD_ENUM,
        type_=_NEW_ENUM,
        existing_nullable=True,
    )


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        return

    op.alter_column(
        'sales', 'status',
        existing_type=_NEW_ENUM,
        type_=_OLD_ENUM,
        existing_nullable=True,
    )
