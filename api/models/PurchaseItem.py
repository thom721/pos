from sqlalchemy import Column, String, Integer, Numeric, ForeignKey,Float
from sqlalchemy.orm import relationship
from .base import UUIDBase

class PurchaseItem(UUIDBase):
    __tablename__ = "purchase_items"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    purchase_id = Column(String(36), ForeignKey("purchases.id"), nullable=False)
    product_id = Column(String(36), ForeignKey("products.id"), nullable=False)
    # quantity = Column(Float, nullable=False)

    ordered_qty = Column(Float, nullable=False)
    remaining_qty = Column(Float, nullable=True)
    # unit_price = Column(Float, nullable=False)

    unit_price = Column(Numeric(12, 2), nullable=False)
    subtotal = Column(Numeric(12, 2))

    purchase = relationship("Purchase", back_populates="items")
    product = relationship("Product")
