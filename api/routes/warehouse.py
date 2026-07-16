from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.schemas.warehouse import WarehouseCreate, WarehouseUpdate, WarehouseRead

router = APIRouter(prefix="/api/warehouses", tags=["Warehouses"])


def _get_or_404(db: Session, warehouse_id: str, tenant_id: str) -> Warehouse:
    wh = db.query(Warehouse).filter(
        Warehouse.id == warehouse_id,
        Warehouse.tenant_id == tenant_id,
    ).first()
    if not wh:
        raise HTTPException(404, "Depot introuvable")
    return wh


@router.get("/", response_model=List[WarehouseRead])
def list_warehouses(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_READ)),
):
    return (
        db.query(Warehouse)
        .filter(Warehouse.tenant_id == current_user.tenant_id)
        .order_by(Warehouse.is_default.desc(), Warehouse.name)
        .all()
    )


@router.post("/", response_model=WarehouseRead, status_code=201)
def create_warehouse(
    data: WarehouseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_CREATE)),
):
    wh = Warehouse(
        tenant_id=current_user.tenant_id,
        name=data.name,
        description=data.description,
        is_active=True,
        is_default=False,
    )
    db.add(wh)
    db.commit()
    db.refresh(wh)
    return wh


@router.get("/{warehouse_id}", response_model=WarehouseRead)
def get_warehouse(
    warehouse_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_READ)),
):
    return _get_or_404(db, warehouse_id, current_user.tenant_id)


@router.put("/{warehouse_id}", response_model=WarehouseRead)
def update_warehouse(
    warehouse_id: str,
    data: WarehouseUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_UPDATE)),
):
    wh = _get_or_404(db, warehouse_id, current_user.tenant_id)
    if data.name is not None:
        wh.name = data.name
    if data.description is not None:
        wh.description = data.description
    if data.is_active is not None:
        if wh.is_default and not data.is_active:
            raise HTTPException(400, "Impossible de desactiver le depot par defaut")
        wh.is_active = data.is_active
    db.commit()
    db.refresh(wh)
    return wh


@router.put("/{warehouse_id}/set-default", response_model=WarehouseRead)
def set_default_warehouse(
    warehouse_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_UPDATE)),
):
    wh = _get_or_404(db, warehouse_id, current_user.tenant_id)
    # Retire l'ancien défaut
    db.query(Warehouse).filter(
        Warehouse.tenant_id == current_user.tenant_id,
        Warehouse.is_default == True,  # noqa: E712
    ).update({"is_default": False})
    wh.is_default = True
    db.commit()
    db.refresh(wh)
    return wh


@router.delete("/{warehouse_id}", response_model=dict)
def delete_warehouse(
    warehouse_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_DELETE)),
):
    wh = _get_or_404(db, warehouse_id, current_user.tenant_id)
    if wh.is_default:
        raise HTTPException(400, "Impossible de supprimer le depot par defaut")
    wh.is_active = False
    db.commit()
    return {"ok": True}
