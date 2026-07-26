"""encrypt pos_register billing dates (trial/subscription) with Fernet per-register key

Les colonnes trial_ends_at, subscription_started_at et subscription_ends_at de
pos_registers passent de DATETIME à TEXT pour stocker des tokens Fernet chiffrés
avec une clé dérivée par register_id (HKDF-SHA256).

Revision ID: s5t6u7v8w9x0
Revises: r3e4g5s6u7b8
"""
from alembic import op
import sqlalchemy as sa

revision = 's5t6u7v8w9x0'
down_revision = 'r3e4g5s6u7b8'
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


def _col_type(table: str, column: str) -> str:
    """Retourne le DATA_TYPE de la colonne (ex: 'datetime', 'text', 'varchar')."""
    bind = op.get_bind()
    result = bind.execute(sa.text(
        "SELECT DATA_TYPE FROM information_schema.columns "
        "WHERE table_schema = DATABASE() "
        "AND table_name = :t AND column_name = :c"
    ), {"t": table, "c": column})
    row = result.fetchone()
    return row[0].lower() if row else ''


def _encrypt_existing(bind, date_col: str, tmp_col: str):
    """Lit les valeurs DATETIME existantes, les chiffre, et les écrit dans tmp_col."""
    from api.core.billing_crypto import encrypt_register_date
    from datetime import timezone

    rows = bind.execute(sa.text(
        f"SELECT id, {date_col} FROM pos_registers WHERE {date_col} IS NOT NULL"
    )).fetchall()

    for row in rows:
        reg_id, dt = row[0], row[1]
        if dt is None:
            continue
        if hasattr(dt, 'tzinfo') and dt.tzinfo is None:
            from datetime import datetime as _dt
            dt = dt.replace(tzinfo=timezone.utc)
        token = encrypt_register_date(dt, reg_id)
        bind.execute(
            sa.text(f"UPDATE pos_registers SET {tmp_col} = :token WHERE id = :id"),
            {"token": token, "id": reg_id},
        )


def upgrade():
    bind = op.get_bind()

    for date_col in ('trial_ends_at', 'subscription_started_at', 'subscription_ends_at'):
        if not _col_exists('pos_registers', date_col):
            # Colonne absente → ajouter directement en TEXT
            op.add_column('pos_registers', sa.Column(date_col, sa.Text(600), nullable=True))
            continue

        current_type = _col_type('pos_registers', date_col)
        if current_type in ('text', 'mediumtext', 'longtext'):
            continue  # Déjà chiffré

        # 1. Colonne temporaire pour accueillir les tokens
        tmp = f'{date_col}_enc'
        if not _col_exists('pos_registers', tmp):
            op.add_column('pos_registers', sa.Column(tmp, sa.Text(600), nullable=True))

        # 2. Chiffrer les données existantes dans la colonne temp
        _encrypt_existing(bind, date_col, tmp)

        # 3. Supprimer l'ancienne colonne DATETIME
        op.drop_column('pos_registers', date_col)

        # 4. Renommer la colonne temp → nom original
        op.alter_column('pos_registers', tmp, new_column_name=date_col)


def downgrade():
    # Downgrade non implémenté — les tokens chiffrés ne peuvent pas être
    # reconvertis en DATETIME sans connaître le SECRET_KEY du serveur.
    pass
