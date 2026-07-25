"""Convertit les contraintes UNIQUE globales en contraintes par tenant

Revision ID: 9d52902ed421
Revises: b2c3d4e5f6g7
Create Date: 2026-07-25

Problème : les colonnes suivantes avaient unique=True au niveau colonne
(contrainte globale sur toute la table), ce qui causait des collisions
silencieuses quand deux tenants différents poussaient un enregistrement
avec la même valeur (ex : VTE-001, admin, Coca Cola).

Fix : suppression de l'ancien index UNIQUE mono-colonne + ajout d'un
UNIQUE KEY composé (colonne, tenant_id).

La migration est idempotente : elle saute les étapes déjà effectuées
(index déjà supprimé ou nouveau composé déjà présent).
"""

from alembic import op
from sqlalchemy import inspect as _inspect

revision = '9d52902ed421'
down_revision = 'b2c3d4e5f6g7'
branch_labels = None
depends_on = None

_TARGETS = [
    ("sales",           "reference", "uq_sale_ref_tenant"),
    ("purchases",       "reference", "uq_purchase_ref_tenant"),
    ("products",        "name",      "uq_product_name_tenant"),
    ("products",        "barcode",   "uq_product_barcode_tenant"),
    ("users",           "username",  "uq_user_username_tenant"),
    ("users",           "email",     "uq_user_email_tenant"),
    ("users",           "phone",     "uq_user_phone_tenant"),
    ("invoices",        "reference", "uq_invoice_ref_tenant"),
    ("proformas",       "reference", "uq_proforma_ref_tenant"),
    ("employee_loans",  "reference", "uq_employee_loan_ref_tenant"),
    ("payroll_periods", "reference", "uq_payroll_period_ref_tenant"),
]


def upgrade():
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        # SQLite (tests locaux) : pas de contraintes globales à migrer
        return

    inspector = _inspect(bind)
    existing_tables = set(inspector.get_table_names())

    for table, col, new_name in _TARGETS:
        if table not in existing_tables:
            continue

        indexes = inspector.get_indexes(table)

        # Déjà migré
        if any(idx["name"] == new_name for idx in indexes):
            continue

        # Supprimer l'ancien index UNIQUE mono-colonne s'il existe
        for idx in indexes:
            if idx.get("unique") and idx.get("column_names") == [col]:
                try:
                    op.drop_index(idx["name"], table_name=table)
                except Exception:
                    pass

        # Créer le nouvel index composé (colonne, tenant_id)
        try:
            op.create_index(new_name, table, [col, "tenant_id"], unique=True)
        except Exception:
            pass


def downgrade():
    bind = op.get_bind()
    if bind.dialect.name != "mysql":
        return

    inspector = _inspect(bind)
    existing_tables = set(inspector.get_table_names())

    for table, col, new_name in _TARGETS:
        if table not in existing_tables:
            continue
        indexes = inspector.get_indexes(table)
        if any(idx["name"] == new_name for idx in indexes):
            try:
                op.drop_index(new_name, table_name=table)
            except Exception:
                pass
        try:
            op.create_index(f"uq_{table}_{col}", table, [col], unique=True)
        except Exception:
            pass
