from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import List

from api.database import get_db
from api.models.Payment import Payment
from api.models.User import User
from api.schemas.payment import PaymentCreate, PaymentResponse
from api.services.payment_service import add_payment
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/payments", tags=["Payments"])


@router.post("/", response_model=PaymentResponse, status_code=201)
def store_payment(
    payload: PaymentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PAYMENTS_CREATE)),
):
    return add_payment(db, payload, current_user.id, tenant_id=current_user.tenant_id)


@router.get("/", response_model=List[PaymentResponse])
def list_payments(
    reference_type: str = Query(..., description="SALE ou PURCHASE"),
    reference_id: str = Query(..., description="UUID de la vente ou de l'achat"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PAYMENTS_READ)),
):
    query = db.query(Payment).filter(
        Payment.reference_type == reference_type.upper(),
        Payment.reference_id == reference_id,
    )
    if current_user.tenant_id:
        query = query.filter(Payment.tenant_id == current_user.tenant_id)
    return query.order_by(Payment.created_at.desc()).all()
