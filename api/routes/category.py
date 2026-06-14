from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Union
from api.services.category_service import CategoryService
from api.schemas.category import CategoryCreate, CategoryRead, CategoryUpdate, CategoryResponse
from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.models.User import User

router = APIRouter(prefix="/api", tags=['Categories'])


@router.post("/categories/", response_model=Union[CategoryResponse, List[CategoryResponse]])
def create_category(
    data: Union[CategoryResponse, List[CategoryResponse]],
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CATEGORIES_CREATE)),
):
    return CategoryService(db, tenant_id=current_user.tenant_id).create(data)


@router.get("/categories/")
def list_categories(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CATEGORIES_READ)),
):
    return {"data": CategoryService(db, tenant_id=current_user.tenant_id).list()}


@router.get("/categories/{category_id}", response_model=CategoryRead)
def get_category(
    category_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CATEGORIES_READ)),
):
    category = CategoryService(db, tenant_id=current_user.tenant_id).get(category_id)
    if not category:
        raise HTTPException(status_code=404, detail="Category not found")
    return category


@router.put("/categories/{category_id}", response_model=CategoryRead)
def update_category(
    category_id: str,
    data: CategoryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CATEGORIES_UPDATE)),
):
    category = CategoryService(db, tenant_id=current_user.tenant_id).update(category_id, data)
    if not category:
        raise HTTPException(status_code=404, detail="Category not found")
    return category


@router.delete("/categories/{category_id}", response_model=dict)
def delete_category(
    category_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CATEGORIES_DELETE)),
):
    success = CategoryService(db, tenant_id=current_user.tenant_id).delete(category_id)
    if not success:
        raise HTTPException(status_code=404, detail="Category not found")
    return {"ok": True}
