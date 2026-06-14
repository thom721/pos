from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime

from api.services.product_service import ProductService
from api.database import get_db
from api.models.User import User
from api.schemas.sale import SaleCreate, SaleUpdate, ProductSaleItem, SaleRead
from api.schemas.common import PaginatedResponse
from api.services.sale_service import create_sale, list_sales, get_sale, cancel_sale, update_sale
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.core.PaginateHelper import PaginatedResponse as LegacyPaginatedResponse

router = APIRouter(prefix="/api/sales", tags=["Sales"])


@router.post("/", status_code=201)
def store_sale(
    payload: SaleCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_CREATE)),
):
    sale = create_sale(db, payload, current_user.id, tenant_id=current_user.tenant_id)
    return {"message": "Vente enregistrée avec succès", "sale_id": sale.id}


@router.get("/", response_model=PaginatedResponse[SaleRead])
def read_sales(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_READ)),
    page: int = Query(1, ge=1),
    limit: int = Query(10, le=100),
    search: Optional[str] = None,
    status: Optional[str] = None,
    date_from: Optional[datetime] = Query(None),
    date_to: Optional[datetime] = Query(None),
):
    return list_sales(db=db, page=page, limit=limit, search=search,
                      status=status, date_from=date_from, date_to=date_to,
                      tenant_id=current_user.tenant_id)


@router.get("/products/search", response_model=LegacyPaginatedResponse[ProductSaleItem])
def search_products_for_sale(
    search: str | None = Query(None, min_length=1),
    page: int = Query(1, ge=1),
    per_page: int = Query(10, ge=1, le=20),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_CREATE)),
):
    return ProductService(db, tenant_id=current_user.tenant_id).list(page=page, per_page=per_page, search=search)


@router.get("/{sale_id}", response_model=SaleRead)
def read_sale(
    sale_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_READ)),
):
    sale = get_sale(db, sale_id, tenant_id=current_user.tenant_id)
    if not sale:
        raise HTTPException(404, "Vente introuvable")
    return sale


@router.put("/{sale_id}")
def update_sale_endpoint(
    sale_id: str,
    payload: SaleUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_UPDATE)),
):
    sale = update_sale(db, sale_id, payload, current_user.id, tenant_id=current_user.tenant_id)
    return {"message": "Vente modifiée avec succès", "sale_id": sale.id}


@router.patch("/{sale_id}/cancel", status_code=200)
def cancel_sale_endpoint(
    sale_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_CANCEL)),
):
    cancel_sale(db, sale_id, current_user.id, tenant_id=current_user.tenant_id)
    return {"message": "Vente annulée avec succès"}
