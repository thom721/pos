from pydantic import BaseModel
from typing import Optional, List
from datetime import date, datetime
from decimal import Decimal


# ── Payroll Period ────────────────────────────────────────────────────────────

class PayrollPeriodCreate(BaseModel):
    label:        str
    period_start: date
    period_end:   date
    pay_date:     date
    notes:        Optional[str] = None


class PayrollPeriodRead(BaseModel):
    id:               str
    reference:        str
    label:            str
    period_start:     date
    period_end:       date
    pay_date:         date
    status:           str
    total_gross:      Decimal
    total_deductions: Decimal
    total_net:        Decimal
    notes:            Optional[str]
    created_at:       datetime

    class Config:
        from_attributes = True


# ── Payroll Entry ─────────────────────────────────────────────────────────────

class PayrollEntryAdjust(BaseModel):
    bonuses:          Optional[Decimal] = None
    other_deductions: Optional[Decimal] = None
    payment_method:   Optional[str]     = None
    notes:            Optional[str]     = None


class LoanDeductionRead(BaseModel):
    loan_id:   str
    amount:    Decimal
    reference: Optional[str] = None

    class Config:
        from_attributes = True


class PayrollEntryRead(BaseModel):
    id:               str
    period_id:        str
    employee_id:      str
    base_salary:      Decimal
    bonuses:          Decimal
    gross_salary:     Decimal
    loan_deduction:   Decimal
    other_deductions: Decimal
    net_salary:       Decimal
    status:           str
    payment_method:   Optional[str]
    notes:            Optional[str]
    paid_at:          Optional[datetime]
    created_at:       datetime

    employee_name:    Optional[str]          = None
    loan_deductions:  List[LoanDeductionRead] = []

    class Config:
        from_attributes = True


# ── Payroll Period with entries ───────────────────────────────────────────────

class PayrollPeriodDetail(PayrollPeriodRead):
    entries: List[PayrollEntryRead] = []
