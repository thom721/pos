"""initial schema — baseline

Revision ID: 2c53e0439622
Revises:
Create Date: 2026-06-14 12:48:08.625156

Ce fichier est un marqueur de départ.
Les tables sont créées par Base.metadata.create_all() au premier démarrage
(voir on_startup dans main.py).  Toutes les modifications de schéma
SUIVANTES doivent être gérées via de nouvelles migrations Alembic.
"""
from typing import Sequence, Union

revision: str = '2c53e0439622'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass  # Schéma initial créé par create_all au premier démarrage


def downgrade() -> None:
    pass
