from pydantic import BaseModel
from typing import Optional, List
from datetime import date, datetime
from decimal import Decimal


# ── Employee Profile ──────────────────────────────────────────────────────────

class EmployeeProfileCreate(BaseModel):
    user_id:          str
    department:       Optional[str]  = None
    position:         Optional[str]  = None
    hire_date:        Optional[date] = None
    base_salary:      Decimal        = Decimal("0")
    salary_type:      str            = "monthly"   # monthly / weekly / daily
    is_active:        bool           = True


class EmployeeProfileUpdate(BaseModel):
    department:       Optional[str]     = None
    position:         Optional[str]     = None
    hire_date:        Optional[date]    = None
    base_salary:      Optional[Decimal] = None
    salary_type:      Optional[str]     = None
    is_active:        Optional[bool]    = None


class EmployeeProfileRead(BaseModel):
    id:               str
    user_id:          str
    department:       Optional[str]
    position:         Optional[str]
    hire_date:        Optional[date]
    base_salary:      Decimal
    salary_type:      str
    is_active:        bool
    created_at:       datetime

    # Embedded user info (joined)
    username:         Optional[str]  = None
    full_name:        Optional[str]  = None
    phone:            Optional[str]  = None

    class Config:
        from_attributes = True


# ── Employee Loan ─────────────────────────────────────────────────────────────

class LoanItemInput(BaseModel):
    name:       str
    quantity:   int    = 1
    unit_price: Decimal
    subtotal:   Decimal


class EmployeeLoanCreate(BaseModel):
    employee_id:       str
    loan_type:         str      = "loan"    # loan | credit_purchase
    description:       Optional[str]  = None
    total_amount:      Decimal
    monthly_deduction: Decimal
    items:             Optional[List[LoanItemInput]] = None


class EmployeeLoanApprove(BaseModel):
    approved: bool = True


class EmployeeLoanRead(BaseModel):
    id:                str
    reference:         str
    employee_id:       str
    loan_type:         str
    description:       Optional[str]
    total_amount:      Decimal
    balance:           Decimal
    monthly_deduction: Decimal
    status:            str
    approved_by:       Optional[str]
    created_by:        Optional[str]
    items_json:        Optional[list]
    created_at:        datetime

    employee_name: Optional[str] = None

    class Config:
        from_attributes = True
