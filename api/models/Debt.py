from sqlalchemy import Column, String, Numeric, ForeignKey, Enum, Index
from sqlalchemy.orm import relationship
from api.models.Purchase import Purchase
from .base import UUIDBase


class Debt(UUIDBase):
    __tablename__ = "debts"

    total_amount   = Column(Numeric(12, 2), nullable=False)
    paid_amount    = Column(Numeric(12, 2), nullable=False, default=0)
    balance        = Column(Numeric(12, 2), nullable=False)
    status         = Column(Enum("UNPAID", "PARTIAL", "PAID", name="debt_status"), nullable=False)
    reference_type = Column(Enum("SALE", "PURCHASE", name="debt_reference_type"), nullable=False)
    reference_id   = Column(String(36), nullable=False)
    partner_type   = Column(Enum("CUSTOMER", "SUPPLIER", name="debt_partner_type"), nullable=False)
    partner_id     = Column(String(36), nullable=False)

    customer = relationship(
        "Customer",
        primaryjoin=(
            "and_("
            "foreign(Debt.partner_id) == Customer.id, "
            "Debt.partner_type == 'CUSTOMER'"
            ")"
        ),
        foreign_keys="[Debt.partner_id]",
        viewonly=True,
    )

    supplier = relationship(
        "Supplier",
        primaryjoin=(
            "and_("
            "foreign(Debt.partner_id) == Supplier.id, "
            "Debt.partner_type == 'SUPPLIER'"
            ")"
        ),
        foreign_keys="[Debt.partner_id]",
        viewonly=True,
    )

    sale = relationship(
        "Sale",
        primaryjoin="and_(Debt.reference_id==Sale.id, Debt.reference_type=='SALE')",
        foreign_keys="[Debt.reference_id]",
        viewonly=True,
    )

    purchase = relationship(
        "Purchase",
        primaryjoin="and_(Debt.reference_id==Purchase.id, Debt.reference_type=='PURCHASE')",
        foreign_keys="[Debt.reference_id]",
        viewonly=True,
    )

    __table_args__ = (
        Index("idx_debt_reference",  "reference_id", "reference_type"),
        Index("idx_debt_partner",    "partner_id",   "partner_type"),
        Index("idx_debt_status",     "status"),
        Index("idx_debt_created_at", "created_at"),
    )

    @property
    def partner_name(self):
        if self.partner_type == "CUSTOMER" and self.customer:
            return self.customer.name
        if self.partner_type == "SUPPLIER" and self.supplier:
            return self.supplier.name
        return None
