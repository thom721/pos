from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional

from api.database import get_db
from api.models.User import User
from api.models.Debt import Debt
from api.schemas.debt import DebtRead
from api.schemas.common import PaginatedResponse
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/debts", tags=["Debts"])


@router.get("/", response_model=PaginatedResponse[DebtRead])
def read_debts(
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.DEBTS_READ)),
    page: int = Query(1, ge=1),
    limit: int = Query(10, le=100),
    partner_type: Optional[str] = Query(None),
    reference_type: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    partner_id: Optional[str] = None,
):
    query = db.query(Debt)

    if partner_type:
        query = query.filter(Debt.partner_type == partner_type.upper())
    if reference_type:
        query = query.filter(Debt.reference_type == reference_type.upper())
    if status:
        query = query.filter(Debt.status == status.upper())
    if partner_id:
        query = query.filter(Debt.partner_id == partner_id)

    total = query.count()
    debts = (
        query.order_by(Debt.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    return {
        "data": debts,
        "meta": {"page": page, "limit": limit, "total": total,
                 "pages": (total + limit - 1) // limit},
    }
