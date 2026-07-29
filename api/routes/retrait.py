from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy.orm import Session

from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.models.User import User
from api.models.Retrait import Retrait
from api.schemas.retrait import RetraitCreate, RetraitRead
from api.services import sabotage_service
from api.services.warehouse_helper import resolve_warehouse_id
from api.ws_manager import manager

router = APIRouter(prefix="/api/retraits", tags=["Retrait"])


@router.post("/", response_model=RetraitRead)
def create_retrait(
    data: RetraitCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.RETRAITS_CREATE)),
):
    warehouse_id = resolve_warehouse_id(db, current_user.tenant_id, data.warehouse_id) \
        or resolve_warehouse_id(db, current_user.tenant_id)
    retrait = sabotage_service.record_retrait(
        db,
        client_id=data.client_id,
        amount=data.amount,
        tenant_id=current_user.tenant_id,
        warehouse_id=warehouse_id,
        user_id=current_user.id,
        note=data.note,
    )
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return retrait


@router.get("/")
def list_retraits(
    client_id: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.RETRAITS_READ)),
):
    q = db.query(Retrait).filter(Retrait.tenant_id == current_user.tenant_id)
    if client_id:
        q = q.filter(Retrait.client_id == client_id)
    return {"data": q.order_by(Retrait.created_at.desc()).all()}
