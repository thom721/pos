from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from api.models.User import User
from api.database import get_db
from api.services.ReceiptService import ReceiptService, get_pending_items
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.schemas.purchase_receipt import PurchaseReceiptCreate

router = APIRouter(prefix="/receive", tags=["Receive"])


@router.post("/", status_code=201)
def store_receipt(
    payload: PurchaseReceiptCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PURCHASES_RECEIVE)),
):
    purchase = ReceiptService(db).receive(payload, current_user.id)
    return {"message": "Livraison enregistrée avec succès", "purchase_id": purchase.id}


@router.get("/{purchase_id}/pending-items")
def pending_items(
    purchase_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PURCHASES_READ)),
):
    return get_pending_items(db, purchase_id)
