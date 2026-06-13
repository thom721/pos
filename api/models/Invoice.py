from sqlalchemy import Column, String, Numeric, Text, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from .base import UUIDBase


class Invoice(UUIDBase):
    __tablename__ = "invoices"

    reference = Column(String(50), unique=True, nullable=False)
    date = Column(DateTime(timezone=True), nullable=False)
    due_date = Column(DateTime(timezone=True), nullable=True)
    client_id = Column(String(36), ForeignKey("customers.id"), nullable=True)
    client_name = Column(String(255), nullable=True)
    discount = Column(Numeric(12, 2), default=0)
    paid_amount = Column(Numeric(12, 2), default=0)
    notes = Column(Text, nullable=True)
    currency = Column(String(10), default="HTG")
    status = Column(String(20), default="draft")  # draft|sent|paid|partial|overdue|cancelled
    user_id = Column(String(36), ForeignKey("users.id"), nullable=True)

    client = relationship("Customer", foreign_keys=[client_id])
    user = relationship("User", foreign_keys=[user_id])
    items = relationship("InvoiceItem", back_populates="invoice",
                         cascade="all, delete-orphan")


class InvoiceItem(UUIDBase):
    __tablename__ = "invoice_items"

    invoice_id = Column(String(36), ForeignKey("invoices.id"), nullable=False)
    product_id = Column(String(36), ForeignKey("products.id"), nullable=True)
    name = Column(String(255), nullable=False)
    quantity = Column(Numeric(12, 3), nullable=False, default=1)
    unit_price = Column(Numeric(12, 2), nullable=False)
    subtotal = Column(Numeric(12, 2), nullable=False)

    invoice = relationship("Invoice", back_populates="items")
    product = relationship("Product", foreign_keys=[product_id])
