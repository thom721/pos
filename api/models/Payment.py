from sqlalchemy import Column, String, Numeric, ForeignKey, Enum, Text, Index
from sqlalchemy.orm import relationship, Mapped
from api.models.Purchase import Purchase
from api.models.Sale import Sale
from .base import UUIDBase


class Payment(UUIDBase):
    __tablename__ = "payments"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    reference_id   = Column(String(36), nullable=False)
    reference_type = Column(
        Enum("SALE", "PURCHASE", name="payement_reference_type"),
        nullable=False,
    )
    amount  = Column(Numeric(12, 2))
    method  = Column(String(20))
    note    = Column(Text, nullable=True)
    user_id = Column(String(36), ForeignKey("users.id"))

    user = relationship("User", back_populates="payments")

    sale: Mapped["Sale"] = relationship(
        "Sale",
        primaryjoin="and_(Payment.reference_id==Sale.id, Payment.reference_type=='SALE')",
        foreign_keys="[Payment.reference_id]",
        viewonly=True,
    )

    purchase: Mapped["Purchase"] = relationship(
        "Purchase",
        primaryjoin="and_(Payment.reference_id==Purchase.id, Payment.reference_type=='PURCHASE')",
        foreign_keys="[Payment.reference_id]",
        viewonly=True,
    )

    __table_args__ = (
        Index("idx_payment_reference", "reference_id", "reference_type"),
        Index("idx_payment_created_at", "created_at"),
    )
