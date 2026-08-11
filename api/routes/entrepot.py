from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import List, Optional

from api.database import get_db
from api.models.User import User
from api.schemas.product import ProductRead
from api.core.PaginateHelper import PaginatedResponse
from api.schemas.entrepot import (
    EntrepotCreate, EntrepotUpdate, EntrepotRead, StockAdjustRequest, DistributeRequest,
    TransferInRequest, TransferReceipt,
)
from api.services.product_service import ProductService
from api.services import entrepot_service
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/entrepot", tags=["Entrepot"])


@router.get("/", response_model=List[EntrepotRead])
def list_entrepots(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_READ)),
):
    return entrepot_service.list_entrepots(db, current_user.tenant_id)


@router.post("/", response_model=EntrepotRead, status_code=201)
def store_entrepot(
    payload: EntrepotCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_CREATE)),
):
    return entrepot_service.create_entrepot(
        db, current_user.tenant_id, payload.name, payload.address,
        payload.linked_warehouse_id,
    )


@router.patch("/{entrepot_id}", response_model=EntrepotRead)
def patch_entrepot(
    entrepot_id: str,
    payload: EntrepotUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_CREATE)),
):
    fields = payload.model_dump(exclude_unset=True)
    return entrepot_service.update_entrepot(
        db, current_user.tenant_id, entrepot_id,
        name=fields.get("name"), address=fields.get("address"),
        linked_warehouse_id=fields.get("linked_warehouse_id", ...),
    )


@router.get("/{entrepot_id}/products", response_model=PaginatedResponse[ProductRead])
def read_entrepot_products(
    entrepot_id: str,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_READ)),
):
    entrepot = entrepot_service.get_entrepot_by_id(db, current_user.tenant_id, entrepot_id)
    return ProductService(db, tenant_id=current_user.tenant_id).list(
        page=page, per_page=per_page, search=search, warehouse_id=entrepot.id,
        # L'entrepôt doit voir TOUS les produits pour pouvoir les distribuer,
        # même ceux rattachés à un dépôt précis (Product.warehouse_id).
        restrict_to_warehouse=False,
    )


@router.post("/{entrepot_id}/products/{product_id}/adjust", response_model=ProductRead)
def adjust_entrepot_product_stock(
    entrepot_id: str,
    product_id: str,
    payload: StockAdjustRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_CREATE)),
):
    return entrepot_service.adjust_entrepot_stock(
        db, current_user.tenant_id, entrepot_id, product_id,
        payload.quantity, payload.reason, current_user.id,
    )


@router.post("/{entrepot_id}/products/{product_id}/distribute", status_code=200)
def distribute_entrepot_product(
    entrepot_id: str,
    product_id: str,
    payload: DistributeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_CREATE)),
):
    entrepot_service.distribute(
        db, current_user.tenant_id, entrepot_id, product_id,
        [a.model_dump() for a in payload.allocations],
        current_user.id,
    )
    return {"message": "Distribution effectuée avec succès"}


@router.post(
    "/{entrepot_id}/products/{product_id}/transfer-in",
    response_model=TransferReceipt,
)
def transfer_in_entrepot_product(
    entrepot_id: str,
    product_id: str,
    payload: TransferInRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.ENTREPOT_CREATE)),
):
    """Envoie du stock vers cet entrepôt — depuis un dépôt classique
    (« retourner à l'entrepôt » sur la fiche produit) ou un autre entrepôt."""
    return entrepot_service.transfer_to_entrepot(
        db, current_user.tenant_id, entrepot_id,
        payload.source_warehouse_id, product_id, payload.quantity,
        current_user.id, payload.reason,
    )
