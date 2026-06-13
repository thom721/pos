from sqlalchemy import Column, String, Numeric, Enum, ForeignKey, Index
from sqlalchemy.orm import relationship
from sqlalchemy.ext.hybrid import hybrid_property
import enum
from .base import UUIDBase


class SaleStatus(enum.Enum):
    unpaid  = "UNPAID"
    paid    = "PAID"
    partial = "partial"
    credit  = "credit"
    pending = "pending"


class Sale(UUIDBase):
    __tablename__ = "sales"

    customer_id  = Column(String(36), ForeignKey("customers.id"), nullable=True)
    user_id      = Column(String(36), ForeignKey("users.id"))
    reference    = Column(String(255), unique=True, nullable=False)
    total_amount = Column(Numeric(12, 2), nullable=False)
    discount     = Column(Numeric(12, 2), default=0)
    final_amount = Column(Numeric(12, 2), default=0)
    paid_amount  = Column(Numeric(12, 2), default=0)
    status       = Column(Enum(SaleStatus), default=SaleStatus.unpaid)

    customer = relationship("Customer", back_populates="sales")
    user     = relationship("User", back_populates="sales")
    items    = relationship("SaleItem", back_populates="sale")

    payments = relationship(
        "Payment",
        primaryjoin=(
            "and_("
            "foreign(Payment.reference_id) == Sale.id, "
            "Payment.reference_type == 'SALE'"
            ")"
        ),
        foreign_keys="[Payment.reference_id]",
        back_populates="sale",
        viewonly=True,
    )

    debts = relationship(
        "Debt",
        primaryjoin=(
            "and_("
            "foreign(Debt.reference_id) == Sale.id, "
            "Debt.reference_type == 'SALE'"
            ")"
        ),
        foreign_keys="[Debt.reference_id]",
        back_populates="sale",
        viewonly=True,
    )

    __table_args__ = (
        Index("idx_sale_customer_id", "customer_id"),
        Index("idx_sale_status",      "status"),
        Index("idx_sale_created_at",  "created_at"),
    )

    @hybrid_property
    def balance(self):
        return self.final_amount - self.paid_amount
