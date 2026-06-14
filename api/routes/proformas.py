from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from api.database import get_db
from api.models.User import User
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.schemas.proforma import ProformaCreate, ProformaRead, ProformaUpdate
from api.services import proforma_service

router = APIRouter(prefix="/api/proformas", tags=["Proformas"])


@router.get("/", response_model=dict)
def list_proformas(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PROFORMAS_READ)),
):
    return proforma_service.list_proformas(db, page=page, limit=limit, tenant_id=current_user.tenant_id)


@router.get("/{proforma_id}", response_model=ProformaRead)
def get_proforma(
    proforma_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PROFORMAS_READ)),
):
    return proforma_service.get_proforma(db, proforma_id, tenant_id=current_user.tenant_id)


@router.post("/", response_model=ProformaRead)
def create_proforma(
    data: ProformaCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PROFORMAS_CREATE)),
):
    return proforma_service.create_proforma(db, data, user_id=current_user.id, tenant_id=current_user.tenant_id)


@router.put("/{proforma_id}", response_model=ProformaRead)
def update_proforma(
    proforma_id: str,
    data: ProformaUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PROFORMAS_UPDATE)),
):
    return proforma_service.update_proforma(db, proforma_id, data, tenant_id=current_user.tenant_id)


@router.delete("/{proforma_id}", response_model=dict)
def delete_proforma(
    proforma_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PROFORMAS_DELETE)),
):
    proforma_service.delete_proforma(db, proforma_id, tenant_id=current_user.tenant_id)
    return {"ok": True}
