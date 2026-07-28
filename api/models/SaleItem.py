from sqlalchemy import Column, String, Integer, Numeric, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase

class SaleItem(UUIDBase):
    __tablename__ = "sale_items"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    sale_id    = Column(String(36), ForeignKey("sales.id"))
    product_id = Column(String(36), ForeignKey("products.id"), nullable=True)
    label      = Column(String(255), nullable=True)  # nom du plat si pas de product_id

    quantity       = Column(Numeric(12, 2), nullable=False)
    unit_price     = Column(Numeric(12, 2), nullable=False)
    original_price = Column(Numeric(12, 2), nullable=True)
    subtotal       = Column(Numeric(12, 2), nullable=False)
    discount       = Column(Numeric(12, 2), default=0, nullable=False)
    discount_id    = Column(String(36), ForeignKey("discounts.id"), nullable=True)

    sale             = relationship("Sale",     back_populates="items")
    product          = relationship("Product")
    discount_catalog = relationship("Discount", foreign_keys=[discount_id])
