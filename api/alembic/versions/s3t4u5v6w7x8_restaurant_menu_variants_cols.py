"""restaurant: menu_items.variants, modifier_groups.menu_item_id, order_items.menu_item_id

Colonnes ajoutées lors du développement du mode restaurant (menu items, variantes de prix,
groupes de modificateurs liés au plat, commandes mixtes menu/stock).

Revision ID: s3t4u5v6w7x8
Revises: r2s3t4u5v6w7
Create Date: 2026-07-19
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

revision: str = 's3t4u5v6w7x8'
down_revision: Union[str, None] = 'r2s3t4u5v6w7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return bool(n)


def upgrade() -> None:
    # ── users ─────────────────────────────────────────────────────────────────
    if not _col_exists('users', 'offline_hash'):
        op.add_column('users',
            sa.Column('offline_hash', sa.String(64), nullable=True))

    # Élargir phone à 255 si elle existe déjà (était VARCHAR(20))
    if _col_exists('users', 'phone'):
        op.alter_column('users', 'phone',
                        existing_type=sa.String(20),
                        type_=sa.String(255),
                        existing_nullable=True)

    # ── modifier_groups ───────────────────────────────────────────────────────
    if not _col_exists('modifier_groups', 'menu_item_id'):
        op.add_column('modifier_groups',
            sa.Column('menu_item_id', sa.String(36), nullable=True))
        op.create_index('ix_modifier_groups_menu_item_id',
                        'modifier_groups', ['menu_item_id'])

    if not _col_exists('modifier_groups', 'warehouse_id'):
        op.add_column('modifier_groups',
            sa.Column('warehouse_id', sa.String(36), nullable=True))

    # ── restaurant_order_items ────────────────────────────────────────────────
    if not _col_exists('restaurant_order_items', 'menu_item_id'):
        op.add_column('restaurant_order_items',
            sa.Column('menu_item_id', sa.String(36), nullable=True))

    # product_id devient nullable (commandes de plats du menu n'ont pas de product_id)
    if _col_exists('restaurant_order_items', 'product_id'):
        op.alter_column('restaurant_order_items', 'product_id',
                        existing_type=sa.String(36),
                        nullable=True)

    # ── menu_items ────────────────────────────────────────────────────────────
    if not _col_exists('menu_items', 'warehouse_id'):
        op.add_column('menu_items',
            sa.Column('warehouse_id', sa.String(36), nullable=True))

    if not _col_exists('menu_items', 'variants'):
        op.add_column('menu_items',
            sa.Column('variants', mysql.JSON(), nullable=True))


def downgrade() -> None:
    if _col_exists('menu_items', 'variants'):
        op.drop_column('menu_items', 'variants')
    if _col_exists('menu_items', 'warehouse_id'):
        op.drop_column('menu_items', 'warehouse_id')
    if _col_exists('restaurant_order_items', 'menu_item_id'):
        op.drop_column('restaurant_order_items', 'menu_item_id')
    if _col_exists('modifier_groups', 'warehouse_id'):
        op.drop_column('modifier_groups', 'warehouse_id')
    if _col_exists('modifier_groups', 'menu_item_id'):
        op.drop_index('ix_modifier_groups_menu_item_id', 'modifier_groups')
        op.drop_column('modifier_groups', 'menu_item_id')
    if _col_exists('users', 'offline_hash'):
        op.drop_column('users', 'offline_hash')
