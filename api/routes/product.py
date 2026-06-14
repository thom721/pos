import uuid
import os
import shutil
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.orm import Session
from typing import List, Optional, Union
from api.services.product_service import ProductService
from api.schemas.product import ProductCreate, ProductRead, ProductUpdate
from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.core.PaginateHelper import PaginatedResponse
from api.models.Product import Product
from api.models.User import User

router = APIRouter(prefix="/api", tags=["Products"])


@router.post("/products/", response_model=Union[ProductRead, List[ProductRead]])
def create_product(
    data: Union[ProductCreate, List[ProductCreate]],
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PRODUCTS_CREATE)),
):
    return ProductService(db, tenant_id=current_user.tenant_id).create(data)


@router.get("/products/", response_model=PaginatedResponse[ProductRead])
def list_products(
    page: int = Query(1, ge=1),
    per_page: int = Query(5, ge=1, le=100),
    search: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PRODUCTS_READ)),
):
    return ProductService(db, tenant_id=current_user.tenant_id).list(page=page, per_page=per_page, search=search)


@router.get("/products/{product_id}", response_model=ProductRead)
def get_product(
    product_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PRODUCTS_READ)),
):
    product = ProductService(db, tenant_id=current_user.tenant_id).get(product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@router.put("/products/{product_id}", response_model=ProductRead)
def update_product(
    product_id: str,
    data: ProductUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PRODUCTS_UPDATE)),
):
    product = ProductService(db, tenant_id=current_user.tenant_id).update(product_id, data)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@router.delete("/products/{product_id}", response_model=dict)
def delete_product(
    product_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PRODUCTS_DELETE)),
):
    success = ProductService(db, tenant_id=current_user.tenant_id).delete(product_id)
    if not success:
        raise HTTPException(status_code=404, detail="Product not found")
    return {"ok": True}


_ALLOWED_EXTS = {'.jpg', '.jpeg', '.png', '.webp', '.gif'}
_PRODUCTS_DIR = "api/static/products"


@router.post("/products/{product_id}/image", response_model=dict)
async def upload_product_image(
    product_id: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PRODUCTS_UPDATE)),
):
    product = db.get(Product, product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    ext = os.path.splitext(file.filename or '')[1].lower()
    if ext not in _ALLOWED_EXTS:
        raise HTTPException(status_code=400, detail="Format non supporté. Utilisez jpg, png ou webp.")

    if product.image_url:
        old_path = os.path.join("api", product.image_url.lstrip("/"))
        if os.path.exists(old_path):
            os.remove(old_path)

    os.makedirs(_PRODUCTS_DIR, exist_ok=True)
    filename = f"{uuid.uuid4()}{ext}"
    save_path = os.path.join(_PRODUCTS_DIR, filename)

    with open(save_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    product.image_url = f"/static/products/{filename}"
    db.commit()

    return {"image_url": product.image_url}
