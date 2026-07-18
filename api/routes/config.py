import os
import shutil
from typing import Optional
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy.orm import Session
from api.database import get_db
from api.models.User import User
from api.schemas.config import ConfigRead, ConfigUpdate
from api.services import config_service
from api.dependencies.auth import require_permission
from api.core.permissions import P
import uuid as _uuid

_LOGOS_DIR = "api/static/logos"
_ALLOWED_EXTS = {'.jpg', '.jpeg', '.png', '.webp', '.gif'}

router = APIRouter(prefix="/api/config", tags=["Config"])


def _wh_id(current_user: User, warehouse_id: Optional[str]) -> Optional[str]:
    """Resolve the effective warehouse_id:
    prefer the client-supplied value, fall back to the user's own warehouse."""
    return warehouse_id or getattr(current_user, 'warehouse_id', None) or None


@router.get("/", response_model=ConfigRead)
def get_config(
    warehouse_id: Optional[str] = Query(None, description="ID du dépôt actif"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    return config_service.get_or_create(
        db,
        tenant_id=current_user.tenant_id,
        warehouse_id=_wh_id(current_user, warehouse_id),
    )


@router.put("/", response_model=ConfigRead)
def update_config(
    data: ConfigUpdate,
    warehouse_id: Optional[str] = Query(None, description="ID du dépôt actif"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_UPDATE)),
):
    return config_service.update(
        db,
        data.model_dump(exclude_none=True),
        tenant_id=current_user.tenant_id,
        warehouse_id=_wh_id(current_user, warehouse_id),
    )


@router.post("/logo", response_model=ConfigRead)
async def upload_logo(
    warehouse_id: Optional[str] = Query(None, description="ID du dépôt actif"),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_UPDATE)),
):
    ext = os.path.splitext(file.filename or '')[1].lower()
    if ext not in _ALLOWED_EXTS:
        raise HTTPException(status_code=400, detail="Format non supporté. Utilisez jpg, png ou webp.")

    wid = _wh_id(current_user, warehouse_id)
    config = config_service.get_or_create(
        db, tenant_id=current_user.tenant_id, warehouse_id=wid
    )
    if config.logo_path:
        old_path = os.path.join("api", config.logo_path.lstrip("/"))
        if os.path.exists(old_path):
            os.remove(old_path)

    os.makedirs(_LOGOS_DIR, exist_ok=True)
    filename = f"{_uuid.uuid4()}{ext}"
    save_path = os.path.join(_LOGOS_DIR, filename)
    with open(save_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    return config_service.update(
        db,
        {'logo_path': f"/static/logos/{filename}"},
        tenant_id=current_user.tenant_id,
        warehouse_id=wid,
    )
