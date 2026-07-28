"""normalize sale status casing to uppercase

Revision ID: acac0d9c1008
Revises: c3d9e93eada3
Create Date: 2026-07-28 14:25:19.931681

Contexte : avant 9b01df8bde55, l'ENUM natif MySQL de sales.status avait des
libellés en minuscules ('unpaid','paid','partial','credit','pending' — pas de
'cancelled' du tout). MySQL normalise toujours la valeur stockée sur la casse
du libellé déclaré, donc même si le code envoyait "PAID"/"UNPAID" (majuscules),
toutes les lignes historiques ont été physiquement stockées en minuscules.
Et comme 'CANCELLED' n'existait pas comme libellé, toute vente annulée a été
tronquée par MySQL à la chaîne vide '' (comportement standard MySQL pour une
valeur ENUM hors-liste en mode non strict).

9b01df8bde55 a élargi l'ENUM en majuscules — les lignes historiques (minuscules
ou '') ne correspondent plus à aucune valeur connue, d'où un LookupError au
niveau de l'API. Cette migration aligne les données existantes sur la nouvelle
casse.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'acac0d9c1008'
down_revision: Union[str, Sequence[str], None] = 'c3d9e93eada3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute(sa.text("UPDATE sales SET status = UPPER(status) WHERE status <> UPPER(status)"))
    # '' = valeur ENUM invalide historique — seul 'CANCELLED' n'existait pas
    # dans l'ancien ENUM, donc toute ligne '' provient forcément de là.
    op.execute(sa.text("UPDATE sales SET status = 'CANCELLED' WHERE status = ''"))


def downgrade() -> None:
    """Downgrade schema."""
    # Normalisation de données — non réversible proprement (la casse d'origine
    # par ligne n'est plus connue), pas d'action.
    pass
