"""backfill null discount columns

Revision ID: 7408f808927a
Revises: 9b01df8bde55
Create Date: 2026-07-28 11:13:33.702525

Contexte : la migration 3d6ef4310920 a ajouté sale_items.discount avec
server_default='0', mais les lignes déjà existantes en base ont été relues
avec une valeur NULL (le server_default n'a pas été rejoué pour l'historique
sur certaines installations MySQL) — provoquant une erreur de validation
Pydantic sur GET /api/sales/. On backfill à 0 puis on verrouille la colonne
en NOT NULL pour empêcher toute récidive.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as _inspect


# revision identifiers, used by Alembic.
revision: str = '7408f808927a'
down_revision: Union[str, Sequence[str], None] = '9b01df8bde55'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(bind, table: str, column: str) -> bool:
    return column in {c["name"] for c in _inspect(bind).get_columns(table)}


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()

    if _has_column(bind, "sale_items", "discount"):
        op.execute(sa.text("UPDATE sale_items SET discount = 0 WHERE discount IS NULL"))
        with op.batch_alter_table("sale_items") as batch:
            batch.alter_column(
                "discount",
                existing_type=sa.Numeric(12, 2),
                nullable=False,
                server_default="0",
            )

    if _has_column(bind, "sales", "discount"):
        op.execute(sa.text("UPDATE sales SET discount = 0 WHERE discount IS NULL"))
        with op.batch_alter_table("sales") as batch:
            batch.alter_column(
                "discount",
                existing_type=sa.Numeric(12, 2),
                nullable=False,
                server_default="0",
            )


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()

    if _has_column(bind, "sale_items", "discount"):
        with op.batch_alter_table("sale_items") as batch:
            batch.alter_column(
                "discount",
                existing_type=sa.Numeric(12, 2),
                nullable=True,
            )

    if _has_column(bind, "sales", "discount"):
        with op.batch_alter_table("sales") as batch:
            batch.alter_column(
                "discount",
                existing_type=sa.Numeric(12, 2),
                nullable=True,
            )
