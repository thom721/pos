from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from api.services.supplier_service import SupplierService
from api.schemas.supplier import SupplierCreate, SupplierRead, SupplierUpdate
from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.models.User import User

router = APIRouter(prefix="", tags=['Suppliers'])


@router.post("/suppliers/", response_model=SupplierRead)
def create_supplier(
    data: SupplierCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.SUPPLIERS_CREATE)),
):
    return SupplierService(db).create(data)


@router.get("/suppliers/", response_model=List[SupplierRead])
def list_suppliers(
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.SUPPLIERS_READ)),
):
    return SupplierService(db).list()


@router.get("/suppliers/{supplier_id}", response_model=SupplierRead)
def get_supplier(
    supplier_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.SUPPLIERS_READ)),
):
    supplier = SupplierService(db).get(supplier_id)
    if not supplier:
        raise HTTPException(status_code=404, detail="Supplier not found")
    return supplier


@router.put("/suppliers/{supplier_id}", response_model=SupplierRead)
def update_supplier(
    supplier_id: str,
    data: SupplierUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.SUPPLIERS_UPDATE)),
):
    supplier = SupplierService(db).update(supplier_id, data)
    if not supplier:
        raise HTTPException(status_code=404, detail="Supplier not found")
    return supplier


@router.delete("/suppliers/{supplier_id}", response_model=dict)
def delete_supplier(
    supplier_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.SUPPLIERS_DELETE)),
):
    success = SupplierService(db).delete(supplier_id)
    if not success:
        raise HTTPException(status_code=404, detail="Supplier not found")
    return {"ok": True}
