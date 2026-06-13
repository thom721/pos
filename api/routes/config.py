from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from api.database import get_db
from api.models.User import User
from api.schemas.config import ConfigRead, ConfigUpdate
from api.services import config_service
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/config", tags=["Config"])


@router.get("/", response_model=ConfigRead)
def get_config(
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.CONFIG_READ)),
):
    return config_service.get_or_create(db)


@router.put("/", response_model=ConfigRead)
def update_config(
    data: ConfigUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.CONFIG_UPDATE)),
):
    return config_service.update(db, data.model_dump(exclude_none=True))
