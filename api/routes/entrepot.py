from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional

from api.database import get_db
from api.models.User import User
from api.schemas.warehouse import WarehouseRead
from api.schemas.product import ProductRead
from api.schemas.common import PaginatedResponse
from api.schemas.entrepot import EntrepotCreate, StockAdjustRequest, DistributeRequest
from api.services.product_service import ProductService
from api.services import entrepot_service
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/entrepot", tags=["Entrepot"])


@router.get("/", response_model=Optional[WarehouseRead])
def read_entrepot(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_READ)),
):
    return entrepot_service.get_entrepot(db, current_user.tenant_id)


@router.post("/", response_model=WarehouseRead, status_code=201)
def store_entrepot(
    payload: EntrepotCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_CREATE)),
):
    return entrepot_service.create_entrepot(db, current_user.tenant_id, payload.name)


@router.get("/products", response_model=PaginatedResponse[ProductRead])
def read_entrepot_products(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_READ)),
):
    entrepot = entrepot_service.get_entrepot(db, current_user.tenant_id)
    if not entrepot:
        raise HTTPException(404, "Entrepôt introuvable — créez-le d'abord")
    return ProductService(db, tenant_id=current_user.tenant_id).list(
        page=page, per_page=per_page, search=search, warehouse_id=entrepot.id,
    )


@router.post("/products/{product_id}/adjust", response_model=ProductRead)
def adjust_entrepot_product_stock(
    product_id: str,
    payload: StockAdjustRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_CREATE)),
):
    return entrepot_service.adjust_entrepot_stock(
        db, current_user.tenant_id, product_id,
        payload.quantity, payload.reason, current_user.id,
    )


@router.post("/products/{product_id}/distribute", status_code=200)
def distribute_entrepot_product(
    product_id: str,
    payload: DistributeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_CREATE)),
):
    entrepot_service.distribute(
        db, current_user.tenant_id, product_id,
        [a.model_dump() for a in payload.allocations],
        current_user.id,
    )
    return {"message": "Distribution effectuée avec succès"}
