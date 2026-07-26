"""pos_registers: corriger is_initial pour caisses créées avant la colonne

Pour chaque tenant qui n'a aucune caisse marquée is_initial=True,
marquer la plus ancienne caisse active comme is_initial=True.

Ces caisses existaient avant l'ajout de la colonne (server_default=0).

Revision ID: c3d4e5f6g7h8
Revises: a1b2c3d4e5f6
Create Date: 2026-07-26
"""
from alembic import op
import sqlalchemy as sa

revision = 'c3d4e5f6g7h8'
down_revision = 'a1b2c3d4e5f6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(sa.text("""
        UPDATE pos_registers pr
        INNER JOIN (
            SELECT pr2.tenant_id, MIN(pr2.created_at) AS min_created
            FROM pos_registers pr2
            WHERE pr2.is_active = 1
            GROUP BY pr2.tenant_id
            HAVING SUM(CASE WHEN pr2.is_initial = 1 THEN 1 ELSE 0 END) = 0
        ) oldest
            ON pr.tenant_id = oldest.tenant_id
           AND pr.created_at = oldest.min_created
        SET pr.is_initial = 1
        WHERE pr.is_active = 1
    """))


def downgrade() -> None:
    pass  # Non réversible — sûr : seule la valeur par défaut est restaurée
