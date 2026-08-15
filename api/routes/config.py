import os
import shutil
from typing import Optional
from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy.orm import Session
from api.database import get_db
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.models.AppConfig import AppConfig
from api.schemas.config import ConfigRead, ConfigUpdate
from api.services import config_service
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.ws_manager import manager
import uuid as _uuid

_LOGOS_DIR = "api/static/logos"
_ALLOWED_EXTS = {'.jpg', '.jpeg', '.png', '.webp', '.gif'}

router = APIRouter(prefix="/api/config", tags=["Config"])


def _wh_id(db: Session, current_user: User, warehouse_id: Optional[str]) -> Optional[str]:
    """Resolve the effective warehouse_id:
    prefer the client-supplied value (validated to belong to the caller's own
    tenant — sans cette vérification, un warehouse_id d'un AUTRE tenant serait
    accepté tel quel et créerait un AppConfig cross-tenant, cf. bug corrigé),
    fall back to the user's own warehouse.
    User.warehouse_id is stored as a JSON list — extract first element."""
    if warehouse_id:
        owned = db.query(Warehouse.id).filter(
            Warehouse.id == warehouse_id,
            Warehouse.tenant_id == current_user.tenant_id,
        ).first()
        if owned:
            return warehouse_id
        return None
    raw = getattr(current_user, 'warehouse_id', None)
    if isinstance(raw, list):
        return raw[0] if raw else None
    return raw or None


async def _notify(tenant_id: Optional[str]) -> None:
    """Notifie via WebSocket tous les devices du tenant que la config a changé."""
    if tenant_id:
        await manager.notify(tenant_id)


def _with_global_logo(db: Session, config, tenant_id: Optional[str]) -> ConfigRead:
    """Le logo est l'identité de marque du tenant, jamais d'un dépôt précis —
    contrairement aux autres réglages (imprimante, etc.), il ne doit jamais
    diverger entre dépôts. AppConfig étant scindé par (tenant_id, warehouse_id),
    une ligne par-dépôt créée avant un upload de logo depuis le web (qui écrit
    sur la ligne globale, warehouse_id NULL) restait bloquée sur son ancienne
    copie pour toujours. On force donc toujours la valeur de la ligne globale
    ici, à la lecture, plutôt que de compter sur une copie figée à la création.
    """
    result = ConfigRead.model_validate(config)
    if tenant_id and config.warehouse_id is not None:
        row = db.query(AppConfig.logo_path).filter(
            AppConfig.tenant_id == tenant_id,
            AppConfig.warehouse_id.is_(None),
        ).first()
        if row:
            result.logo_path = row[0]
    return result


@router.get("/", response_model=ConfigRead)
def get_config(
    warehouse_id: Optional[str] = Query(None, description="ID du dépôt actif"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    config = config_service.get_or_create(
        db,
        tenant_id=current_user.tenant_id,
        warehouse_id=_wh_id(db, current_user, warehouse_id),
    )
    return _with_global_logo(db, config, current_user.tenant_id)


@router.put("/", response_model=ConfigRead)
def update_config(
    data: ConfigUpdate,
    background_tasks: BackgroundTasks,
    warehouse_id: Optional[str] = Query(None, description="ID du dépôt actif"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_UPDATE)),
):
    fields = data.model_dump(exclude_none=True)
    # logo_path est global au tenant (voir _with_global_logo) — jamais écrit
    # sur une ligne par-dépôt, sinon elle divergerait à nouveau de la ligne
    # globale au prochain upload de logo depuis un autre appareil/le web.
    logo_path = fields.pop('logo_path', None)
    if logo_path is not None:
        config_service.update(
            db, {'logo_path': logo_path},
            tenant_id=current_user.tenant_id, warehouse_id=None,
        )
    result = config_service.update(
        db,
        fields,
        tenant_id=current_user.tenant_id,
        warehouse_id=_wh_id(db, current_user, warehouse_id),
    )
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _with_global_logo(db, result, current_user.tenant_id)


@router.post("/logo", response_model=ConfigRead)
async def upload_logo(
    background_tasks: BackgroundTasks,
    warehouse_id: Optional[str] = Query(None, description="ID du dépôt actif"),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_UPDATE)),
):
    ext = os.path.splitext(file.filename or '')[1].lower()
    if ext not in _ALLOWED_EXTS:
        raise HTTPException(status_code=400, detail="Format non supporté. Utilisez jpg, png ou webp.")

    # Le logo est toujours écrit sur la ligne globale du tenant (warehouse_id
    # NULL), jamais sur celle d'un dépôt précis — voir _with_global_logo :
    # un logo uploadé depuis le web (sans dépôt actif) doit se refléter sur
    # tous les dépôts/appareils du tenant, pas seulement celui de l'uploadeur.
    global_config = config_service.get_or_create(
        db, tenant_id=current_user.tenant_id, warehouse_id=None
    )
    if global_config.logo_path:
        old_path = os.path.join("api", global_config.logo_path.lstrip("/"))
        if os.path.exists(old_path):
            os.remove(old_path)

    os.makedirs(_LOGOS_DIR, exist_ok=True)
    filename = f"{_uuid.uuid4()}{ext}"
    save_path = os.path.join(_LOGOS_DIR, filename)
    with open(save_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    result = config_service.update(
        db,
        {'logo_path': f"/static/logos/{filename}"},
        tenant_id=current_user.tenant_id,
        warehouse_id=None,
    )
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _with_global_logo(db, result, current_user.tenant_id)
