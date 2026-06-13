from fastapi import APIRouter, Depends, Query
from typing import Optional
from sqlalchemy.orm import Session

from api.database import get_db
from api.schemas.SaleReturnItem import SaleReturnPayload, PurchaseReturnPayload
from api.services.return_service import process_sale_return, process_purchase_return, list_returns
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.models.User import User

router = APIRouter(tags=["Returns"])


@router.get("/")
def get_returns(
    return_type: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.RETURNS_READ)),
):
    return list_returns(db, return_type=return_type, page=page, limit=limit)


@router.post("/sale")
def sale_return(
    payload: SaleReturnPayload,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.RETURNS_CREATE)),
):
    refund_total = process_sale_return(
        db=db,
        sale_id=str(payload.sale_id),
        items=[item.dict() for item in payload.items],
        refund_amount=payload.refund_amount,
        user_id=current_user.id,
        reason=payload.reason,
    )
    return {"message": "Retour client effectué", "refund_total": refund_total}


@router.post("/purchase")
def purchase_return(
    payload: PurchaseReturnPayload,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.RETURNS_CREATE)),
):
    return_total = process_purchase_return(
        db=db,
        purchase_id=str(payload.purchase_id),
        items=[item.dict() for item in payload.items],
        user_id=current_user.id,
        reason=payload.reason,
    )
    return {"message": "Retour fournisseur effectué", "return_total": return_total}
