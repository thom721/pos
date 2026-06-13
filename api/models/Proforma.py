from sqlalchemy import Column, String, Numeric, Text, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from .base import UUIDBase


class Proforma(UUIDBase):
    __tablename__ = "proformas"

    reference = Column(String(50), unique=True, nullable=False)
    date = Column(DateTime(timezone=True), nullable=False)
    client_id = Column(String(36), ForeignKey("customers.id"), nullable=True)
    client_name = Column(String(255), nullable=True)
    discount = Column(Numeric(12, 2), default=0)
    notes = Column(Text, nullable=True)
    currency = Column(String(10), default="HTG")
    status = Column(String(20), default="draft")  # draft|sent|accepted|cancelled
    user_id = Column(String(36), ForeignKey("users.id"), nullable=True)

    client = relationship("Customer", foreign_keys=[client_id])
    user = relationship("User", foreign_keys=[user_id])
    items = relationship("ProformaItem", back_populates="proforma",
                         cascade="all, delete-orphan")


class ProformaItem(UUIDBase):
    __tablename__ = "proforma_items"

    proforma_id = Column(String(36), ForeignKey("proformas.id"), nullable=False)
    product_id = Column(String(36), ForeignKey("products.id"), nullable=True)
    name = Column(String(255), nullable=False)
    quantity = Column(Numeric(12, 3), nullable=False, default=1)
    unit_price = Column(Numeric(12, 2), nullable=False)
    subtotal = Column(Numeric(12, 2), nullable=False)

    proforma = relationship("Proforma", back_populates="items")
    product = relationship("Product", foreign_keys=[product_id])
