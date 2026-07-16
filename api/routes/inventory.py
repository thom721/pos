import json
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional, List

from api.database import get_db
from api.models.User import User
from api.schemas.inventory import InventoryCreate, InventoryRead, InventoryPreviewItem
from api.services.inventory_service import get_preview, list_inventories, get_inventory, create_inventory
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/inventory", tags=["Inventory"])


@router.get("/preview")
def preview_inventory(
    category_ids: Optional[List[str]] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.INVENTORY_READ)),
):
    return {"data": get_preview(db, category_ids, tenant_id=current_user.tenant_id)}


@router.get("/")
def read_inventories(
    page: int = Query(1, ge=1),
    limit: int = Query(20, le=100),
    warehouse_id: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.INVENTORY_READ)),
):
    return list_inventories(db, page=page, limit=limit,
                            tenant_id=current_user.tenant_id,
                            warehouse_id=warehouse_id)


@router.get("/{inventory_id}")
def read_inventory(
    inventory_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.INVENTORY_READ)),
):
    record = get_inventory(db, inventory_id, tenant_id=current_user.tenant_id)
    if not record:
        raise HTTPException(404, "Inventaire introuvable")
    try:
        items = json.loads(record.items_json or "[]")
    except Exception:
        items = []
    return {
        "id": record.id,
        "reference": record.reference,
        "inventory_type": record.inventory_type,
        "status": record.status,
        "notes": record.notes,
        "total_products": record.total_products,
        "discrepancy_count": record.discrepancy_count,
        "created_at": record.created_at.isoformat(),
        "items": items,
    }


@router.post("/", status_code=201)
def store_inventory(
    payload: InventoryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.INVENTORY_CREATE)),
):
    record = create_inventory(db, payload, current_user.id, tenant_id=current_user.tenant_id,
                              warehouse_id=payload.warehouse_id)
    return {
        "message": "Inventaire enregistré avec succès",
        "inventory_id": record.id,
        "reference": record.reference,
        "discrepancy_count": record.discrepancy_count,
    }
