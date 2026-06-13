from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional

from api.database import get_db
from api.models.User import User
from api.schemas.employee import (
    EmployeeProfileCreate, EmployeeProfileUpdate, EmployeeProfileRead,
    EmployeeLoanCreate, EmployeeLoanRead,
)
from api.services import employee_service
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/hr", tags=["HR"])


# ── Employee Profiles ─────────────────────────────────────────────────────────

@router.get("/employees/", response_model=list)
def list_employees(
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.EMPLOYEES_READ)),
):
    return employee_service.list_employee_profiles(db)


@router.get("/employees/{profile_id}")
def get_employee(
    profile_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.EMPLOYEES_READ)),
):
    return employee_service.get_employee_profile(db, profile_id)


@router.get("/employees/by-user/{user_id}")
def get_employee_by_user(
    user_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.EMPLOYEES_READ)),
):
    return employee_service.get_profile_by_user(db, user_id)


@router.post("/employees/", status_code=201)
def create_employee(
    data: EmployeeProfileCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.EMPLOYEES_CREATE)),
):
    return employee_service.create_employee_profile(db, data)


@router.put("/employees/{profile_id}")
def update_employee(
    profile_id: str,
    data: EmployeeProfileUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.EMPLOYEES_UPDATE)),
):
    return employee_service.update_employee_profile(db, profile_id, data)


# ── Loans ─────────────────────────────────────────────────────────────────────

@router.get("/loans/")
def list_loans(
    employee_id: Optional[str] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.LOANS_READ)),
):
    return employee_service.list_loans(db, employee_id=employee_id, status=status)


@router.post("/loans/", status_code=201)
def create_loan(
    data: EmployeeLoanCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.LOANS_CREATE)),
):
    return employee_service.create_loan(db, data, created_by=current_user.id)


@router.patch("/loans/{loan_id}/approve")
def approve_loan(
    loan_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.LOANS_APPROVE)),
):
    return employee_service.approve_loan(db, loan_id, approved_by=current_user.id)


@router.patch("/loans/{loan_id}/cancel")
def cancel_loan(
    loan_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.LOANS_APPROVE)),
):
    return employee_service.cancel_loan(db, loan_id)
