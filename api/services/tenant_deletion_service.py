"""Suppression complète et irréversible d'un tenant — action superadmin.

Nettoie TOUTES les tables tenant_id-scopées (~45, voir TENANT_SCOPED_MODELS)
en une seule transaction, avant de supprimer le tenant lui-même. Les
contraintes FK sont temporairement désactivées (MySQL: FOREIGN_KEY_CHECKS,
SQLite: PRAGMA foreign_keys) pour ne pas dépendre d'un ordre de suppression
précis entre les tables — sans ça, il faudrait trier ~45 tables selon leurs
dépendances FK, fragile à maintenir à chaque nouvelle table ajoutée.

Filtre systématiquement sur tenant_id == tenant_id cible : aucune autre
table/tenant n'est jamais touchée, quel que soit l'ordre ou le contenu.
"""
import logging

from sqlalchemy import text
from sqlalchemy.orm import Session

from api.models.Tenant import Tenant
from api.models.AppConfig import AppConfig
from api.models.AuditLog import AuditLog
from api.models.BillingExtra import BillingExtra
from api.models.BillingPayment import BillingPayment
from api.models.CashierSession import CashierSession
from api.models.Category import Category
from api.models.ClientSabotage import ClientSabotage
from api.models.Customer import Customer
from api.models.Debt import Debt
from api.models.Depot import Depot
from api.models.Discount import Discount
from api.models.EmployeeLoan import EmployeeLoan
from api.models.EmployeeProfile import EmployeeProfile
from api.models.HousekeepingTask import HousekeepingTask
from api.models.Ingredient import Ingredient
from api.models.InstallationCode import InstallationCode
from api.models.InventoryRecord import InventoryRecord
from api.models.Invoice import Invoice, InvoiceItem
from api.models.MenuItem import MenuItem
from api.models.ModifierGroup import ModifierGroup, ModifierOption
from api.models.OfflineSyncQueue import OfflineSyncQueue
from api.models.Payment import Payment
from api.models.PayrollEntry import PayrollEntry
from api.models.PayrollLoanDeduction import PayrollLoanDeduction
from api.models.PayrollPeriod import PayrollPeriod
from api.models.PosRegister import PosRegister
from api.models.Product import Product
from api.models.ProductWarehousePrice import ProductWarehousePrice
from api.models.Proforma import Proforma, ProformaItem
from api.models.Purchase import Purchase
from api.models.PurchaseItem import PurchaseItem
from api.models.PurchaseReceipt import PurchaseReceipt
from api.models.PurchaseReceiptItem import PurchaseReceiptItem
from api.models.RestaurantOrder import RestaurantOrder, RestaurantOrderItem
from api.models.RestaurantTable import RestaurantTable
from api.models.Retrait import Retrait
from api.models.ReturnRecord import ReturnRecord
from api.models.Role import Role
from api.models.RoomAttribute import RoomAttribute
from api.models.Sale import Sale
from api.models.SaleItem import SaleItem
from api.models.StockMovement import StockMovement
from api.models.Supplier import Supplier
from api.models.User import User
from api.models.Warehouse import Warehouse

_log = logging.getLogger("pos.tenant_deletion")

# Tous les modèles portant tenant_id — tenu à jour manuellement. Le test
# test_tenant_scoped_models_list_is_complete (test_tenant_deletion.py)
# échoue si un nouveau modèle avec tenant_id est ajouté sans être listé
# ici, pour éviter une fuite de données orphelines silencieuse.
# Items (lignes) AVANT leurs parents (Invoice/Proforma/RestaurantOrder) —
# ordre indifférent en pratique (FK désactivées pendant la suppression)
# mais gardé lisible/cohérent.
TENANT_SCOPED_MODELS = [
    AuditLog, BillingExtra, BillingPayment, CashierSession,
    ClientSabotage, Debt, Depot, Discount, EmployeeLoan, EmployeeProfile,
    HousekeepingTask, Ingredient, InstallationCode, InventoryRecord,
    InvoiceItem, Invoice, MenuItem, ModifierOption, ModifierGroup,
    OfflineSyncQueue, Payment, PayrollLoanDeduction, PayrollEntry, PayrollPeriod,
    PosRegister, ProductWarehousePrice, ProformaItem, Proforma,
    PurchaseItem, PurchaseReceiptItem, PurchaseReceipt, Purchase,
    RestaurantOrderItem, RestaurantOrder, RestaurantTable, Retrait,
    ReturnRecord, RoomAttribute, SaleItem, Sale, StockMovement,
    Supplier, Category, Customer, Product, Role, User, Warehouse, AppConfig,
]


def delete_tenant_completely(db: Session, tenant_id: str) -> dict[str, int] | None:
    """Supprime le tenant et toutes ses données. Retourne None si le tenant
    n'existe pas, sinon {table: nb_lignes_supprimées} (tables avec 0 ligne
    omises). Irréversible — aucune corbeille, aucun undo."""
    tenant = db.get(Tenant, tenant_id)
    if not tenant:
        return None

    dialect = db.get_bind().dialect.name
    counts: dict[str, int] = {}

    try:
        if dialect == "mysql":
            db.execute(text("SET FOREIGN_KEY_CHECKS=0"))
        else:
            db.execute(text("PRAGMA foreign_keys=OFF"))

        for model in TENANT_SCOPED_MODELS:
            n = (
                db.query(model)
                .filter(model.tenant_id == tenant_id)
                .delete(synchronize_session=False)
            )
            if n:
                counts[model.__tablename__] = n

        db.delete(tenant)
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        # Pas transactionnel (variable de session MySQL / pragma SQLite) —
        # doit être ré-activé même si la suppression a échoué et roll-back.
        try:
            if dialect == "mysql":
                db.execute(text("SET FOREIGN_KEY_CHECKS=1"))
            else:
                db.execute(text("PRAGMA foreign_keys=ON"))
            db.commit()
        except Exception:
            pass

    _log.warning("Tenant supprimé définitivement : %s (%s) — %s",
                 tenant.slug, tenant_id, counts)
    return counts
