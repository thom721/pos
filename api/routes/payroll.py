from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from api.database import get_db
from api.models.User import User
from api.schemas.payroll import PayrollPeriodCreate, PayrollEntryAdjust
from api.services import payroll_service
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/payroll", tags=["Payroll"])


@router.get("/periods/")
def list_periods(
    page: int = Query(1, ge=1),
    limit: int = Query(20, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.PAYROLL_READ)),
):
    return payroll_service.list_periods(db, page=page, limit=limit)


@router.get("/periods/{period_id}")
def get_period(
    period_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.PAYROLL_READ)),
):
    return payroll_service.get_period_detail(db, period_id)


@router.post("/periods/", status_code=201)
def create_period(
    data: PayrollPeriodCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PAYROLL_CREATE)),
):
    return payroll_service.create_period(db, data, created_by=current_user.id)


@router.post("/periods/{period_id}/process")
def process_period(
    period_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.PAYROLL_PROCESS)),
):
    return payroll_service.process_period(db, period_id)


@router.post("/periods/{period_id}/pay")
def pay_period(
    period_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.PAYROLL_PAY)),
):
    return payroll_service.pay_period(db, period_id)


@router.post("/periods/{period_id}/cancel")
def cancel_period(
    period_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.PAYROLL_CREATE)),
):
    return payroll_service.cancel_period(db, period_id)


@router.patch("/entries/{entry_id}/adjust")
def adjust_entry(
    entry_id: str,
    data: PayrollEntryAdjust,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.PAYROLL_PROCESS)),
):
    return payroll_service.adjust_entry(db, entry_id, data)
