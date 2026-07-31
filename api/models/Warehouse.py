from sqlalchemy import Column, String, Boolean, Text, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from .base import UUIDBase


class Warehouse(UUIDBase):
    __tablename__ = "warehouses"

    tenant_id   = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)
    name        = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    is_active   = Column(Boolean, nullable=False, default=True)
    is_default  = Column(Boolean, nullable=False, default=False)
    is_claimed  = Column(Boolean, nullable=False, default=False)
    # Entrepôt central (stock de transit, distribué vers les dépôts de vente) —
    # un seul par tenant. Exclu du décompte de facturation des dépôts
    # (api/routes/billing.py::_compute_plan_usage) mais volontairement PAS
    # exclu de la liste générale des dépôts (sert de destination de réception
    # d'achat comme n'importe quel dépôt).
    is_entrepot = Column(Boolean, nullable=False, default=False)

    stock_movements    = relationship("StockMovement",    back_populates="warehouse")
    purchases          = relationship("Purchase",         back_populates="warehouse")
    purchase_receipts  = relationship("PurchaseReceipt",  back_populates="warehouse")
    inventory_records  = relationship("InventoryRecord",  back_populates="warehouse")
    pos_registers      = relationship("PosRegister",      back_populates="warehouse")
    sales              = relationship("Sale",             back_populates="warehouse")
    cashier_sessions   = relationship("CashierSession",   back_populates="warehouse")
    return_records     = relationship("ReturnRecord",     back_populates="warehouse")

    __table_args__ = (
        UniqueConstraint("name", "tenant_id", name="uq_warehouse_name_tenant"),
    )
