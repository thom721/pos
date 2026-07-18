import uuid as _uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Body, Depends, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import List, Optional

from api.database import get_db
from api.dependencies.auth import get_current_user, require_permission
from api.core.permissions import P
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.models.Tenant import Tenant
from api.models.PlatformConfig import PlatformConfig
from api.schemas.warehouse import WarehouseCreate, WarehouseUpdate, WarehouseRead
from api.services import billing_extra_service as _billing


def _pricing(db: Session) -> PlatformConfig | None:
    return db.query(PlatformConfig).first()


def _limit_response(resource: str, current: int, max_: int, cfg: PlatformConfig | None):
    """Return a 402 JSON response when a tenant exceeds caisse/dépôt limits."""
    if resource == "caisse":
        price_htg = float(cfg.price_per_extra_caisse_htg) if cfg else 500.0
        price_usd = float(cfg.price_per_extra_caisse_usd) if cfg else 4.0
    else:
        price_htg = float(cfg.price_per_extra_depot_htg) if cfg else 500.0
        price_usd = float(cfg.price_per_extra_depot_usd) if cfg else 4.0
    return JSONResponse(
        status_code=402,
        content={
            "detail":   "limit_exceeded",
            "resource": resource,
            "current":  current,
            "max":      max_,
            "price_htg": price_htg,
            "price_usd": price_usd,
        },
    )


class RegisterRead(BaseModel):
    id: str
    name: str
    device_id: str
    is_active: bool
    warehouse_id: Optional[str] = None

    class Config:
        from_attributes = True


class RegisterCreate(BaseModel):
    name: str
    device_id: Optional[str] = None  # auto-généré si absent
    force: bool = False  # bypass limit check after user confirmation


class RegisterUpdate(BaseModel):
    name: Optional[str] = None
    is_active: Optional[bool] = None

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
        .filter(
            Warehouse.tenant_id == current_user.tenant_id,
            Warehouse.is_active == True,  # noqa: E712
        )
        .order_by(Warehouse.is_default.desc(), Warehouse.name)
        .all()
    )


@router.post("/", status_code=201)
def create_warehouse(
    data: WarehouseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_CREATE)),
):
    if not data.force:
        tenant = db.get(Tenant, current_user.tenant_id)
        if tenant:
            current_count = db.query(Warehouse).filter_by(
                tenant_id=current_user.tenant_id, is_active=True
            ).count()
            if current_count >= tenant.max_depots:
                return _limit_response("dépôt", current_count, tenant.max_depots, _pricing(db))

    tenant = db.get(Tenant, current_user.tenant_id)
    active_before = db.query(Warehouse).filter_by(
        tenant_id=current_user.tenant_id, is_active=True
    ).count()

    wh = Warehouse(
        tenant_id=current_user.tenant_id,
        name=data.name,
        description=data.description,
        is_active=True,
        is_default=False,
    )
    db.add(wh)
    db.flush()

    # Record extra if this depot exceeds the plan limit (force confirmed by user)
    if data.force and tenant and active_before >= tenant.max_depots:
        _billing.record_extra(db, current_user.tenant_id, "depot", wh.id)

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
        if wh.is_active and not data.is_active:
            _billing.close_extra(db, wh.id)
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
    _billing.close_extra(db, wh.id)
    wh.is_active = False
    db.commit()
    return {"ok": True}


# ── Caisses (PosRegister) par dépôt ──────────────────────────────────────────

def _get_register_or_404(db: Session, warehouse_id: str, register_id: str,
                          tenant_id: str) -> PosRegister:
    reg = db.query(PosRegister).filter(
        PosRegister.id == register_id,
        PosRegister.warehouse_id == warehouse_id,
        PosRegister.tenant_id == tenant_id,
    ).first()
    if not reg:
        raise HTTPException(404, "Caisse introuvable")
    return reg


@router.get("/{warehouse_id}/registers", response_model=List[RegisterRead])
def list_registers(
    warehouse_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_READ)),
):
    _get_or_404(db, warehouse_id, current_user.tenant_id)
    return (
        db.query(PosRegister)
        .filter(
            PosRegister.warehouse_id == warehouse_id,
            PosRegister.tenant_id == current_user.tenant_id,
        )
        .order_by(PosRegister.name)
        .all()
    )


@router.post("/{warehouse_id}/registers", status_code=201)
def create_register(
    warehouse_id: str,
    data: RegisterCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_UPDATE)),
):
    _get_or_404(db, warehouse_id, current_user.tenant_id)

    if not data.force:
        tenant = db.get(Tenant, current_user.tenant_id)
        if tenant:
            current_count = db.query(PosRegister).filter_by(
                tenant_id=current_user.tenant_id, is_active=True
            ).count()
            if current_count >= tenant.max_caisses:
                return _limit_response("caisse", current_count, tenant.max_caisses, _pricing(db))

    device_id = data.device_id or str(_uuid.uuid4())
    reg = PosRegister(
        tenant_id=current_user.tenant_id,
        warehouse_id=warehouse_id,
        name=data.name,
        device_id=device_id,
        is_active=True,
    )
    db.add(reg)
    db.commit()
    db.refresh(reg)
    return reg


@router.put("/{warehouse_id}/registers/{register_id}", response_model=RegisterRead)
def update_register(
    warehouse_id: str,
    register_id: str,
    data: RegisterUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_UPDATE)),
):
    reg = _get_register_or_404(db, warehouse_id, register_id, current_user.tenant_id)
    if data.name is not None:
        reg.name = data.name
    if data.is_active is not None:
        if reg.is_active and not data.is_active:
            _billing.close_extra(db, reg.id)
        reg.is_active = data.is_active
    db.commit()
    db.refresh(reg)
    return reg


@router.delete("/{warehouse_id}/registers/{register_id}", response_model=dict)
def delete_register(
    warehouse_id: str,
    register_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_DELETE)),
):
    reg = _get_register_or_404(db, warehouse_id, register_id, current_user.tenant_id)
    _billing.close_extra(db, reg.id)
    db.delete(reg)
    db.commit()
    return {"ok": True}


@router.post("/registers/heartbeat")
def register_heartbeat(
    device_id: str = Body(..., embed=True),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Updates last_seen for the calling device's register (keeps the session slot alive)."""
    register = db.query(PosRegister).filter(
        PosRegister.tenant_id == current_user.tenant_id,
        PosRegister.device_id == device_id,
    ).first()
    if register:
        register.last_seen = datetime.now(timezone.utc)
        db.commit()
    return {"ok": True}


@router.post("/registers/logout")
def register_logout(
    device_id: str = Body(..., embed=True),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Frees the register slot immediately on explicit logout (clears last_seen + session_token)."""
    register = db.query(PosRegister).filter(
        PosRegister.tenant_id == current_user.tenant_id,
        PosRegister.device_id == device_id,
    ).first()
    if register:
        register.last_seen = None
        register.session_token = None
        db.commit()
    return {"ok": True}
