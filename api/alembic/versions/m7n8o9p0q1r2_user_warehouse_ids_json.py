"""users.warehouse_id : VARCHAR → JSON (tableau de dépôts autorisés)

Revision ID: m7n8o9p0q1r2
Revises: l6m7n8o9p0q1
Create Date: 2026-07-16
"""
from typing import Sequence, Union
import json as _json

from alembic import op
import sqlalchemy as sa

revision: str = 'm7n8o9p0q1r2'
down_revision: Union[str, None] = 'l6m7n8o9p0q1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn    = op.get_bind()
    dialect = conn.dialect.name

    # Idempotence : déjà migré si la colonne est de type JSON
    if dialect == 'mysql':
        dt = conn.execute(sa.text(
            "SELECT DATA_TYPE FROM information_schema.COLUMNS "
            "WHERE TABLE_SCHEMA = DATABASE() "
            "AND TABLE_NAME = 'users' AND COLUMN_NAME = 'warehouse_id'"
        )).scalar()
        if dt and dt.lower() == 'json':
            return

    # 1. Lire les valeurs UUID existantes avant toute modification
    rows = conn.execute(sa.text(
        "SELECT id, warehouse_id FROM users WHERE warehouse_id IS NOT NULL AND warehouse_id != ''"
    )).fetchall()
    # Ne garder que les valeurs qui ne sont pas déjà un tableau JSON
    to_migrate = [
        (str(r[0]), str(r[1]))
        for r in rows
        if r[1] and not str(r[1]).strip().startswith('[')
    ]

    if dialect == 'mysql':
        # 2. Supprimer FK et index avant de toucher au type
        try:
            op.drop_constraint('fk_user_warehouse', 'users', type_='foreignkey')
        except Exception:
            pass
        try:
            op.drop_index('ix_user_warehouse_id', table_name='users')
        except Exception:
            pass

        # 3. Mettre à NULL les valeurs non-JSON pour que MySQL puisse faire l'ALTER
        if to_migrate:
            conn.execute(sa.text(
                "UPDATE users SET warehouse_id = NULL WHERE warehouse_id IS NOT NULL"
            ))

        # 4. Changer le type en JSON (l'ALTER MySQL cause un commit implicite)
        op.alter_column(
            'users', 'warehouse_id',
            existing_type=sa.String(36),
            type_=sa.JSON(),
            nullable=True,
        )

        # 5. Restaurer les valeurs sous forme de tableau JSON
        for uid, wid in to_migrate:
            conn.execute(sa.text(
                "UPDATE users SET warehouse_id = :v WHERE id = :id"
            ), {"v": _json.dumps([wid]), "id": uid})

    else:
        # SQLite : mettre à jour les valeurs textuelles d'abord, puis batch alter
        for uid, wid in to_migrate:
            conn.execute(sa.text(
                "UPDATE users SET warehouse_id = :v WHERE id = :id"
            ), {"v": _json.dumps([wid]), "id": uid})
        with op.batch_alter_table('users') as batch_op:
            batch_op.alter_column(
                'warehouse_id',
                type_=sa.JSON(),
                existing_nullable=True,
            )


def downgrade() -> None:
    conn    = op.get_bind()
    dialect = conn.dialect.name

    # Lire les tableaux JSON existants
    rows = conn.execute(sa.text(
        "SELECT id, warehouse_id FROM users WHERE warehouse_id IS NOT NULL"
    )).fetchall()
    to_restore = []
    for r in rows:
        try:
            lst = _json.loads(str(r[1])) if r[1] else None
            if isinstance(lst, list) and lst:
                to_restore.append((str(r[0]), str(lst[0])))
        except Exception:
            pass

    if dialect == 'mysql':
        if to_restore:
            conn.execute(sa.text(
                "UPDATE users SET warehouse_id = NULL WHERE warehouse_id IS NOT NULL"
            ))
        op.alter_column(
            'users', 'warehouse_id',
            existing_type=sa.JSON(),
            type_=sa.String(36),
            nullable=True,
        )
        op.create_foreign_key(
            'fk_user_warehouse', 'users', 'warehouses', ['warehouse_id'], ['id']
        )
        op.create_index('ix_users_warehouse_id', 'users', ['warehouse_id'])
        for uid, wid in to_restore:
            conn.execute(sa.text(
                "UPDATE users SET warehouse_id = :v WHERE id = :id"
            ), {"v": wid, "id": uid})
    else:
        for uid, wid in to_restore:
            conn.execute(sa.text(
                "UPDATE users SET warehouse_id = :v WHERE id = :id"
            ), {"v": wid, "id": uid})
        with op.batch_alter_table('users') as batch_op:
            batch_op.alter_column(
                'warehouse_id',
                type_=sa.String(36),
                existing_nullable=True,
            )
