from sqlalchemy import Column, String, Numeric, ForeignKey, JSON, UniqueConstraint
from sqlalchemy.orm import relationship
from .base import UUIDBase


class EmployeeLoan(UUIDBase):
    __tablename__ = "employee_loans"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    reference          = Column(String(50),  nullable=False, index=True)
    employee_id        = Column(String(36),  ForeignKey("users.id"),  nullable=False, index=True)
    # "loan" | "credit_purchase"
    loan_type          = Column(String(30),  nullable=False, default="loan")
    description        = Column(String(500), nullable=True)
    total_amount       = Column(Numeric(12, 2), nullable=False)
    balance            = Column(Numeric(12, 2), nullable=False)
    monthly_deduction  = Column(Numeric(12, 2), nullable=False)
    # "active" | "paid" | "cancelled"
    status             = Column(String(20),  nullable=False, default="active")
    approved_by        = Column(String(36),  ForeignKey("users.id"), nullable=True)
    created_by         = Column(String(36),  ForeignKey("users.id"), nullable=True)
    # JSON list of items for credit_purchase type
    items_json         = Column(JSON, nullable=True)

    employee = relationship("User", foreign_keys=[employee_id])
    approver = relationship("User", foreign_keys=[approved_by])
    creator  = relationship("User", foreign_keys=[created_by])

    __table_args__ = (
        UniqueConstraint("reference", "tenant_id", name="uq_employee_loan_ref_tenant"),
    )
