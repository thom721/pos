from sqlalchemy import Column, String, Numeric, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class LoanRepayment(UUIDBase):
    """Remboursement manuel d'un prêt employé (cash/moncash/natcash), en
    dehors du cycle de paie normal — voir aussi PayrollLoanDeduction pour
    les déductions automatiques appliquées au paiement d'une période payroll.
    Les deux mécanismes réduisent EmployeeLoan.balance de la même façon."""
    __tablename__ = "loan_repayments"

    tenant_id  = Column(String(36), ForeignKey('tenants.id'),         nullable=True, index=True)
    loan_id    = Column(String(36), ForeignKey('employee_loans.id'),  nullable=False, index=True)
    amount     = Column(Numeric(12, 2), nullable=False)
    # "cash" | "moncash" | "natcash" | "bank_transfer" | "other"
    method     = Column(String(30), nullable=False, default="cash")
    note       = Column(String(500), nullable=True)
    created_by = Column(String(36), ForeignKey('users.id'), nullable=True)

    loan    = relationship("EmployeeLoan")
    creator = relationship("User", foreign_keys=[created_by])
