from sqlalchemy import Column, String, Numeric, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class PayrollLoanDeduction(UUIDBase):
    __tablename__ = "payroll_loan_deductions"

    entry_id  = Column(String(36), ForeignKey("payroll_entries.id"), nullable=False, index=True)
    loan_id   = Column(String(36), ForeignKey("employee_loans.id"),  nullable=False, index=True)
    amount    = Column(Numeric(12, 2), nullable=False)

    entry = relationship("PayrollEntry", back_populates="loan_deductions")
    loan  = relationship("EmployeeLoan")
