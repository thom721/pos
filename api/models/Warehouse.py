from sqlalchemy import Column, String, Boolean, Text, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class Warehouse(UUIDBase):
    __tablename__ = "warehouses"

    tenant_id   = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)
    name        = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    is_active   = Column(Boolean, nullable=False, default=True)
    is_default  = Column(Boolean, nullable=False, default=False)

    stock_movements    = relationship("StockMovement",    back_populates="warehouse")
    purchases          = relationship("Purchase",         back_populates="warehouse")
    purchase_receipts  = relationship("PurchaseReceipt",  back_populates="warehouse")
    inventory_records  = relationship("InventoryRecord",  back_populates="warehouse")
    pos_registers      = relationship("PosRegister",      back_populates="warehouse")
    users              = relationship("User",             back_populates="warehouse",
                                     foreign_keys="[User.warehouse_id]")
