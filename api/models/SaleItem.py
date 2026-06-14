from sqlalchemy import Column, String, Integer, Numeric, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase

class SaleItem(UUIDBase):
    __tablename__ = "sale_items"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    sale_id    = Column(String(36), ForeignKey("sales.id"))
    product_id = Column(String(36), ForeignKey("products.id"))

    quantity       = Column(Numeric(12, 2), nullable=False)
    unit_price     = Column(Numeric(12, 2), nullable=False)
    original_price = Column(Numeric(12, 2), nullable=True)
    subtotal       = Column(Numeric(12, 2), nullable=False)

    sale    = relationship("Sale",    back_populates="items")
    product = relationship("Product")
