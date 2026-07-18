from sqlalchemy import Column, String, Numeric, Enum, ForeignKey, DateTime, Index
from sqlalchemy.orm import relationship
import enum
from .base import UUIDBase
from datetime import datetime, timezone


class PurchaseStatus(enum.Enum):
    pending = "pending"
    partial = "partial"
    paid    = "paid"


class Purchase(UUIDBase):
    __tablename__ = "purchases"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    supplier_id  = Column(String(36), ForeignKey("suppliers.id"), nullable=True)
    user_id      = Column(String(36), ForeignKey("users.id"))
    warehouse_id = Column(String(36), ForeignKey("warehouses.id"), nullable=True, index=True)
    reference    = Column(String(255), unique=True, nullable=False)
    total_amount = Column(Numeric(12, 2))
    paid_amount  = Column(Numeric(12, 2), default=0)
    status       = Column(Enum(PurchaseStatus), default=PurchaseStatus.pending)
    ordered_at   = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    received_at  = Column(DateTime, nullable=True)

    supplier  = relationship("Supplier",   back_populates="purchases")
    user      = relationship("User",       back_populates="purchases")
    warehouse = relationship("Warehouse",  back_populates="purchases")
    items     = relationship("PurchaseItem",    back_populates="purchase")
    receipts  = relationship("PurchaseReceipt", back_populates="purchase")

    payments = relationship(
        "Payment",
        primaryjoin=(
            "and_("
            "foreign(Payment.reference_id) == Purchase.id, "
            "Payment.reference_type == 'PURCHASE'"
            ")"
        ),
        foreign_keys="[Payment.reference_id]",
        back_populates="purchase",
        viewonly=True,
    )

    debts = relationship(
        "Debt",
        primaryjoin=(
            "and_("
            "foreign(Debt.reference_id) == Purchase.id, "
            "Debt.reference_type == 'PURCHASE'"
            ")"
        ),
        foreign_keys="[Debt.reference_id]",
        back_populates="purchase",
        viewonly=True,
    )

    __table_args__ = (
        Index("idx_purchase_supplier_id", "supplier_id"),
        Index("idx_purchase_status",      "status"),
        Index("idx_purchase_created_at",  "created_at"),
    )
