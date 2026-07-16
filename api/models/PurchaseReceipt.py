from sqlalchemy import Column, String, Numeric, Enum, ForeignKey,DateTime,Text
from sqlalchemy.orm import relationship

import enum
from .base import UUIDBase
from datetime import datetime, timezone

class PurchaseStatus(enum.Enum):
    pending = "pending"
    partial = "partial"
    paid = "paid"

class PurchaseReceipt(UUIDBase):
    __tablename__ = "purchase_receipts"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    purchase_id  = Column(ForeignKey("purchases.id"), nullable=False)
    warehouse_id = Column(String(36), ForeignKey("warehouses.id"), nullable=True, index=True)

    received_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    received_by = Column(String(36), nullable=True)
    note        = Column(Text, nullable=True)

    purchase  = relationship("Purchase",  back_populates="receipts")
    warehouse = relationship("Warehouse", back_populates="purchase_receipts")
    items     = relationship("PurchaseReceiptItem", back_populates="receipt")
