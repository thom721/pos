from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy.orm import Session

from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.models.User import User
from api.models.Depot import Depot
from api.schemas.depot import DepotCreate, DepotRead
from api.services import sabotage_service
from api.services.warehouse_helper import resolve_warehouse_id
from api.ws_manager import manager

router = APIRouter(prefix="/api/depots", tags=["Depot"])


@router.post("/", response_model=DepotRead)
def create_depot(
    data: DepotCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.DEPOTS_CREATE)),
):
    warehouse_id = resolve_warehouse_id(db, current_user.tenant_id, data.warehouse_id) \
        or resolve_warehouse_id(db, current_user.tenant_id)
    depot = sabotage_service.record_depot(
        db,
        client_id=data.client_id,
        amount=data.amount,
        tenant_id=current_user.tenant_id,
        warehouse_id=warehouse_id,
        user_id=current_user.id,
        note=data.note,
    )
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return depot


@router.get("/")
def list_depots(
    client_id: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.DEPOTS_READ)),
):
    q = db.query(Depot).filter(Depot.tenant_id == current_user.tenant_id)
    if client_id:
        q = q.filter(Depot.client_id == client_id)
    return {"data": q.order_by(Depot.created_at.desc()).all()}
