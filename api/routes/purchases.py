from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from api.models.User import User
from datetime import datetime
from api.database import get_db
from api.schemas.purchase import PurchaseCreate, PurchaseRead
from api.services.purchase_service import create_purchase, list_purchases, get_purchase
from api.dependencies.auth import require_permission
from api.core.permissions import P
from typing import Optional
from api.schemas.common import PaginatedResponse

router = APIRouter(prefix="/api/purchases", tags=["Purchases"])


@router.post("/", status_code=201)
def store_purchase(
    payload: PurchaseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PURCHASES_CREATE)),
):
    purchase = create_purchase(db, payload, current_user.id)
    return {"message": "Achat enregistré avec succès", "purchase_id": purchase.id}


@router.get("/", response_model=PaginatedResponse[PurchaseRead])
def read_purchases(
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.PURCHASES_READ)),
    page: int = Query(1, ge=1),
    limit: int = Query(10, le=100),
    search: Optional[str] = None,
    status: Optional[str] = None,
    date_from: Optional[datetime] = Query(None),
    date_to: Optional[datetime] = Query(None),
):
    return list_purchases(db=db, page=page, limit=limit, search=search,
                          status=status, date_from=date_from, date_to=date_to)


@router.get("/{purchase_id}", response_model=PurchaseRead)
def read_purchase(
    purchase_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.PURCHASES_READ)),
):
    purchase = get_purchase(db, purchase_id)
    if not purchase:
        raise HTTPException(404, "Achat introuvable")
    return purchase
