from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from sqlalchemy.orm import Session
from api.services.discount_service import DiscountService
from api.schemas.discount import DiscountCreate, DiscountRead, DiscountUpdate
from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.models.User import User
from api.ws_manager import manager

router = APIRouter(prefix="/api", tags=['Discounts'])


@router.post("/discounts/", response_model=DiscountRead)
def create_discount(
    data: DiscountCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.DISCOUNTS_CREATE)),
):
    result = DiscountService(db, tenant_id=current_user.tenant_id).create(data)
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return result


@router.get("/discounts/")
def list_discounts(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.DISCOUNTS_READ)),
):
    return {"data": DiscountService(db, tenant_id=current_user.tenant_id).list()}


@router.get("/discounts/{discount_id}", response_model=DiscountRead)
def get_discount(
    discount_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.DISCOUNTS_READ)),
):
    discount = DiscountService(db, tenant_id=current_user.tenant_id).get(discount_id)
    if not discount:
        raise HTTPException(status_code=404, detail="Rabais introuvable")
    return discount


@router.put("/discounts/{discount_id}", response_model=DiscountRead)
def update_discount(
    discount_id: str,
    data: DiscountUpdate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.DISCOUNTS_UPDATE)),
):
    discount = DiscountService(db, tenant_id=current_user.tenant_id).update(discount_id, data)
    if not discount:
        raise HTTPException(status_code=404, detail="Rabais introuvable")
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return discount


@router.delete("/discounts/{discount_id}", response_model=dict)
def delete_discount(
    discount_id: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.DISCOUNTS_DELETE)),
):
    success = DiscountService(db, tenant_id=current_user.tenant_id).delete(discount_id)
    if not success:
        raise HTTPException(status_code=404, detail="Rabais introuvable")
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return {"ok": True}
