"""add subscription_started_at to pos_registers + init tenant trial on existing rows

Revision ID: r3e4g5s6u7b8
Revises: a1b2c3d4e5f6g7
"""
from alembic import op
import sqlalchemy as sa

revision = 'r3e4g5s6u7b8'
down_revision = 'a1b2c3d4e5f6g7'
branch_labels = None
depends_on = None


def _col_exists(table: str, column: str) -> bool:
    bind = op.get_bind()
    result = bind.execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.columns "
        "WHERE table_schema = DATABASE() "
        "AND table_name = :t AND column_name = :c"
    ), {"t": table, "c": column})
    return result.scalar() > 0


def upgrade():
    # 1. Ajouter la colonne subscription_started_at
    if not _col_exists("pos_registers", "subscription_started_at"):
        op.add_column(
            "pos_registers",
            sa.Column("subscription_started_at", sa.DateTime(timezone=True), nullable=True),
        )

    # 2. Copier trial_ends_at du tenant vers les caisses sans dates propres
    #    (caisses créées avant la facturation par caisse)
    if _col_exists("pos_registers", "trial_ends_at") and _col_exists("tenants", "trial_ends_at"):
        op.execute(sa.text("""
            UPDATE pos_registers pr
            INNER JOIN tenants t ON pr.tenant_id = t.id
            SET pr.trial_ends_at = t.trial_ends_at
            WHERE pr.trial_ends_at IS NULL
              AND pr.subscription_ends_at IS NULL
              AND pr.is_active = 1
              AND t.trial_ends_at IS NOT NULL
        """))


def downgrade():
    if _col_exists("pos_registers", "subscription_started_at"):
        op.drop_column("pos_registers", "subscription_started_at")
