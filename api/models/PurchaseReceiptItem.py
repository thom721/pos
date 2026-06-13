from sqlalchemy import Column, String, Integer, Numeric, ForeignKey,Float
from sqlalchemy.orm import relationship
from .base import UUIDBase

class PurchaseReceiptItem(UUIDBase):
    __tablename__ = "purchase_receipt_items"
 
    purchase_receipt_id = Column(ForeignKey("purchase_receipts.id"))
    purchase_item_id = Column(ForeignKey("purchase_items.id"))

    product_id = Column(String(36), nullable=False)
    received_qty = Column(Float, nullable=False)

    receipt = relationship("PurchaseReceipt", back_populates="items")
