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

    purchase_id = Column(ForeignKey("purchases.id"), nullable=False)

    received_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    received_by = Column(String(36), nullable=True)
    note = Column(Text, nullable=True)

    purchase = relationship("Purchase", back_populates="receipts")
    items = relationship("PurchaseReceiptItem", back_populates="receipt")
