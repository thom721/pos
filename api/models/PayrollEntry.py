from sqlalchemy import Column, String, Numeric, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class PayrollEntry(UUIDBase):
    __tablename__ = "payroll_entries"

    period_id         = Column(String(36),   ForeignKey("payroll_periods.id"), nullable=False, index=True)
    employee_id       = Column(String(36),   ForeignKey("users.id"),           nullable=False, index=True)
    base_salary       = Column(Numeric(12, 2), nullable=False)
    bonuses           = Column(Numeric(12, 2), nullable=False, default=0)
    gross_salary      = Column(Numeric(12, 2), nullable=False)
    loan_deduction    = Column(Numeric(12, 2), nullable=False, default=0)
    other_deductions  = Column(Numeric(12, 2), nullable=False, default=0)
    net_salary        = Column(Numeric(12, 2), nullable=False)
    # "pending" | "paid"
    status            = Column(String(20),   nullable=False, default="pending")
    # "cash" | "bank_transfer" | "check" | "mobile_money"
    payment_method    = Column(String(30),   nullable=True)
    notes             = Column(String(500),  nullable=True)
    paid_at           = Column(DateTime(timezone=True), nullable=True)

    period           = relationship("PayrollPeriod", back_populates="entries")
    employee         = relationship("User", foreign_keys=[employee_id])
    loan_deductions  = relationship("PayrollLoanDeduction", back_populates="entry",
                                    cascade="all, delete-orphan")
