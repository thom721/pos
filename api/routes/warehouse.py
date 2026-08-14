import json as _json
import logging
import uuid as _uuid
from datetime import datetime, timedelta
from fastapi import APIRouter, Body, Depends, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import List, Optional

from api.database import get_db
from api.dependencies.auth import get_current_user, require_permission
from api.core.config import settings
from api.core.permissions import P, has_permission as _has_perm
from api.core.dt_coerce import now_local
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.models.CashierSession import CashierSession
from api.models.Tenant import Tenant
from api.models.PlatformConfig import PlatformConfig
from api.schemas.warehouse import WarehouseCreate, WarehouseUpdate, WarehouseRead
from api.services import billing_extra_service as _billing
from api.services import config_service as _config
from api.services import audit_service
from api.models.InstallationCode import InstallationCode, generate_installation_code

_log = logging.getLogger("pos.register")


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
    device_id: Optional[str] = None
    is_active: bool
    is_device_approved: bool = True
    is_initial: bool = False
    warehouse_id: Optional[str] = None
    trial_ends_at: Optional[datetime] = None
    subscription_started_at: Optional[datetime] = None
    subscription_ends_at: Optional[datetime] = None
    dedicated_user_id: Optional[str] = None
    dedicated_user_name: Optional[str] = None
    app_version: Optional[str] = None
    app_build: Optional[int] = None

    class Config:
        from_attributes = True


class RegisterCreate(BaseModel):
    name: str
    device_id: Optional[str] = None  # auto-généré si absent
    force: bool = False  # bypass limit check after user confirmation


class RegisterUpdate(BaseModel):
    name: Optional[str] = None
    is_active: Optional[bool] = None
    dedicated_user_id: Optional[str] = None  # None = garder, "" = retirer le caissier dédié
    is_device_approved: Optional[bool] = None  # admin approuve l'appareil actuel
    reset_device: bool = False  # libère la caisse (device_id=None) pour un nouvel appareil

router = APIRouter(prefix="/api/warehouses", tags=["Warehouses"])


def _parse_wh_ids(raw) -> list[str]:
    """Normalise user.warehouse_id quelle que soit la forme stockée en DB.

    La colonne est Column(JSON) mais peut être physiquement TEXT dans MySQL.
    SQLAlchemy ne désérialise pas toujours automatiquement TEXT → list.
    Cas supportés :
      - None / [] → []
      - ['uuid', ...]  (déjà une liste Python) → tel quel
      - 'uuid'          (UUID simple en string) → ['uuid']
      - '["uuid", ...]' (JSON string non parsé) → json.loads → liste
    """
    if not raw:
        return []
    if isinstance(raw, list):
        return [str(i) for i in raw if i]
    if isinstance(raw, str):
        s = raw.strip()
        if s.startswith('['):
            try:
                parsed = _json.loads(s)
                if isinstance(parsed, list):
                    return [str(i) for i in parsed if i]
            except _json.JSONDecodeError:
                pass
        return [s] if s else []
    return []


def _get_or_404(db: Session, warehouse_id: str, tenant_id: str) -> Warehouse:
    wh = db.query(Warehouse).filter(
        Warehouse.id == warehouse_id,
        Warehouse.tenant_id == tenant_id,
    ).first()
    if not wh:
        raise HTTPException(404, "Depot introuvable")
    return wh


def _check_name_unique(db: Session, tenant_id: str, name: str, exclude_id: str | None = None) -> None:
    q = db.query(Warehouse).filter(
        Warehouse.tenant_id == tenant_id,
        Warehouse.name == name,
    )
    if exclude_id:
        q = q.filter(Warehouse.id != exclude_id)
    if q.first():
        raise HTTPException(status_code=409, detail=f"Un business nommé « {name} » existe déjà.")


def _check_register_name_unique(db: Session, warehouse_id: str, name: str, exclude_id: str | None = None) -> None:
    q = db.query(PosRegister).filter(
        PosRegister.warehouse_id == warehouse_id,
        PosRegister.name == name,
    )
    if exclude_id:
        q = q.filter(PosRegister.id != exclude_id)
    if q.first():
        raise HTTPException(status_code=409, detail=f"Une caisse nommée « {name} » existe déjà dans ce dépôt.")


@router.get("/", response_model=List[WarehouseRead])
def list_warehouses(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_READ)),
):
    can_see_all = _has_perm(
        current_user.permissions or [],
        current_user.roles or [],
        P.WAREHOUSES_CREATE,  # admin/manager peuvent créer → accès à tous les dépôts
    )
    q = (
        db.query(Warehouse)
        .filter(
            Warehouse.tenant_id == current_user.tenant_id,
            Warehouse.is_active == True,  # noqa: E712
        )
    )
    if not can_see_all:
        allowed = _parse_wh_ids(current_user.warehouse_id)
        if allowed:
            results = (
                q.filter(Warehouse.id.in_(allowed))
                .order_by(Warehouse.is_default.desc(), Warehouse.name)
                .all()
            )
            if results:
                return results
            # Les dépôts assignés n'existent plus en base — fallback sur tous
            # les dépôts actifs du tenant pour éviter un écran vide.
            import logging as _log
            _log.getLogger("pos.api").warning(
                "user %s warehouse_id=%s introuvable → fallback tous dépôts",
                current_user.username, current_user.warehouse_id,
            )
    return q.order_by(Warehouse.is_default.desc(), Warehouse.name).all()


@router.post("/", status_code=201)
def create_warehouse(
    data: WarehouseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_CREATE)),
):
    # Un poste local qui synchronise vers le cloud (CLOUD_SYNC_ENABLED) ne
    # doit jamais créer sa propre ligne de dépôt : deux installations locales
    # pourraient sinon créer chacune un dépôt indépendamment, avec des id
    # différents que la synchro ne peut pas fusionner (pas de repli par nom
    # pour warehouse — voir local_sync_service.py). La création doit passer
    # par le cloud (web), seule source canonique. Un poste non synchronisé
    # (essai autonome, tenant réellement self-hosted sans sync business) n'est
    # pas concerné : rien à faire diverger.
    if settings.CLOUD_SYNC_ENABLED:
        raise HTTPException(
            status_code=403,
            detail="La création d'un dépôt doit se faire depuis le site web (cloud), "
                   "pas depuis ce poste local — pour éviter des doublons non synchronisables.",
        )
    if not data.force:
        tenant = db.get(Tenant, current_user.tenant_id)
        if tenant:
            current_count = db.query(Warehouse).filter_by(
                tenant_id=current_user.tenant_id, is_active=True
            ).count()
            if current_count >= tenant.max_depots:
                return _limit_response("dépôt", current_count, tenant.max_depots, _pricing(db))

    _check_name_unique(db, current_user.tenant_id, data.name)

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

    # Créer automatiquement la config du nouveau dépôt
    _config.create_for_warehouse(db, current_user.tenant_id, wh.id)

    # Caisse initiale du dépôt — slot vide, réclamé par le 1er appareil à se connecter.
    # Trial propre à la caisse, indépendant du tenant.
    _cfg = db.query(PlatformConfig).first()
    _trial_days = int(_cfg.trial_days) if _cfg and _cfg.trial_days else 30
    _now = now_local()
    db.add(PosRegister(
        tenant_id=current_user.tenant_id,
        warehouse_id=wh.id,
        name="Caisse principale",
        is_active=True,
        is_initial=True,
        trial_ends_at=_now + timedelta(days=_trial_days),
    ))

    # Génère automatiquement un code d'installation unique pour ce dépôt
    db.add(InstallationCode(
        code=generate_installation_code(),
        tenant_id=current_user.tenant_id,
        warehouse_id=wh.id,
    ))
    db.commit()

    return wh


@router.get("/{warehouse_id}", response_model=WarehouseRead)
def get_warehouse(
    warehouse_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_READ)),
):
    return _get_or_404(db, warehouse_id, current_user.tenant_id)


@router.get("/{warehouse_id}/install-code")
def get_install_code(
    warehouse_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_READ)),
):
    """Return the installation code for an unclaimed warehouse (null if already claimed)."""
    wh = _get_or_404(db, warehouse_id, current_user.tenant_id)
    if wh.is_claimed:
        return {"code": None, "is_claimed": True}
    ic = db.query(InstallationCode).filter(
        InstallationCode.warehouse_id == warehouse_id,
    ).first()
    if ic is None:
        ic = InstallationCode(
            code=generate_installation_code(),
            tenant_id=current_user.tenant_id,
            warehouse_id=warehouse_id,
        )
        db.add(ic)
        db.commit()
    return {"code": ic.code, "is_claimed": False}


@router.post("/{warehouse_id}/install-code")
def regenerate_install_code(
    warehouse_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_UPDATE)),
):
    """Regenerate the installation code for an unclaimed warehouse."""
    wh = _get_or_404(db, warehouse_id, current_user.tenant_id)
    if wh.is_claimed:
        raise HTTPException(status_code=400, detail="Ce dépôt est déjà installé, impossible de régénérer le code.")
    db.query(InstallationCode).filter(
        InstallationCode.warehouse_id == warehouse_id,
    ).delete()
    ic = InstallationCode(
        code=generate_installation_code(),
        tenant_id=current_user.tenant_id,
        warehouse_id=warehouse_id,
    )
    db.add(ic)
    db.commit()
    return {"code": ic.code}


@router.put("/{warehouse_id}", response_model=WarehouseRead)
def update_warehouse(
    warehouse_id: str,
    data: WarehouseUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_UPDATE)),
):
    wh = _get_or_404(db, warehouse_id, current_user.tenant_id)
    if data.name is not None and data.name != wh.name:
        _check_name_unique(db, current_user.tenant_id, data.name, exclude_id=wh.id)
        wh.name = data.name
    if data.description is not None:
        wh.description = data.description
    if data.is_active is not None:
        if wh.is_default and not data.is_active:
            raise HTTPException(400, "Impossible de desactiver le depot par defaut")
        if wh.is_active and not data.is_active:
            _billing.close_extra(db, wh.id)
        wh.is_active = data.is_active
    if wh.is_entrepot and (data.unlink_warehouse or data.linked_warehouse_id is not None):
        from api.services.entrepot_service import _validate_linked_warehouse
        new_link = None if data.unlink_warehouse else data.linked_warehouse_id
        _validate_linked_warehouse(db, current_user.tenant_id, new_link)
        wh.linked_warehouse_id = new_link
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
    regs = (
        db.query(PosRegister)
        .filter(
            PosRegister.warehouse_id == warehouse_id,
            PosRegister.tenant_id == current_user.tenant_id,
            PosRegister.is_active == True,  # noqa: E712
        )
        .order_by(PosRegister.name)
        .all()
    )
    result = []
    for r in regs:
        d = RegisterRead.model_validate(r)
        if r.dedicated_user_id and r.dedicated_user:
            u = r.dedicated_user
            d.dedicated_user_name = f"{u.fname} {u.lname}".strip() or u.username
        result.append(d)
    return result


@router.post("/{warehouse_id}/registers", status_code=201)
def create_register(
    warehouse_id: str,
    data: RegisterCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_UPDATE)),
):
    wh = _get_or_404(db, warehouse_id, current_user.tenant_id)
    if wh.is_entrepot:
        raise HTTPException(
            400,
            "Un entrepôt ne peut pas avoir de caisse — il sert uniquement "
            "à réceptionner et distribuer du stock.",
        )

    if not data.force:
        tenant = db.get(Tenant, current_user.tenant_id)
        if tenant:
            current_count = db.query(PosRegister).filter_by(
                tenant_id=current_user.tenant_id, is_active=True
            ).count()
            if current_count >= tenant.max_caisses:
                return _limit_response("caisse", current_count, tenant.max_caisses, _pricing(db))

    _check_register_name_unique(db, warehouse_id, data.name)

    device_id = data.device_id or str(_uuid.uuid4())

    # Pas de période d'essai pour une caisse supplémentaire (is_initial=False) —
    # seule la toute première caisse d'un dépôt (is_initial=True, créée par
    # register_tenant/create_warehouse) en bénéficie. Celle-ci doit être payée
    # immédiatement pour être utilisée (voir open_session::register_no_subscription).
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


def _force_close_open_sessions(db: Session, reg: PosRegister, current_user: User) -> None:
    """Ferme de force toute session caisse encore ouverte sur ce registre —
    même logique/calcul que POST /api/sessions/{id}/force-close
    (api/routes/cashier_sessions.py::force_close_session), réutilisée ici
    pour que reset_device libère vraiment la caisse plutôt que de laisser
    une session oubliée la garder indisponible."""
    from api.routes.cashier_sessions import _compute_reconciliation

    open_sessions = db.query(CashierSession).filter(
        CashierSession.register_id == reg.id,
        CashierSession.status == "open",
    ).all()
    for session in open_sessions:
        closed_at = now_local()
        recon = _compute_reconciliation(db, session, closed_at)
        session.closed_at                = closed_at
        session.closing_balance          = 0
        session.status                   = "closed"
        session.total_cash_sales         = recon["total_cash_sales"]
        session.total_card_sales         = recon["total_card_sales"]
        session.total_mobile_sales       = recon["total_mobile_sales"]
        session.total_bank_sales         = recon["total_bank_sales"]
        session.total_refunds_cash       = recon["total_refunds_cash"]
        session.expected_closing_balance = recon["expected_closing_balance"]
        session.cash_difference          = 0 - recon["expected_closing_balance"]

        forced_by = f"{current_user.fname} {current_user.lname}".strip() or current_user.username
        audit_service.log(
            db,
            user_id=current_user.id,
            tenant_id=current_user.tenant_id,
            action="FORCE_CLOSE",
            resource_type="cashier_session",
            resource_id=session.id,
            detail={
                "forced_by":           forced_by,
                "forced_at":           closed_at.isoformat(),
                "original_cashier_id": session.cashier_id,
                "reason":              "reset_device",
            },
        )


@router.put("/{warehouse_id}/registers/{register_id}", response_model=RegisterRead)
def update_register(
    warehouse_id: str,
    register_id: str,
    data: RegisterUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_UPDATE)),
):
    from api.models.User import User as UserModel
    reg = _get_register_or_404(db, warehouse_id, register_id, current_user.tenant_id)
    if data.name is not None and data.name != reg.name:
        _check_register_name_unique(db, warehouse_id, data.name, exclude_id=reg.id)
        reg.name = data.name
    if data.is_active is not None:
        if reg.is_active and not data.is_active:
            _billing.close_extra(db, reg.id)
        reg.is_active = data.is_active
    if data.dedicated_user_id is not None:
        if data.dedicated_user_id == "":
            reg.dedicated_user_id = None
        else:
            # Vérifier que l'utilisateur appartient au même tenant
            target = db.query(UserModel).filter_by(
                id=data.dedicated_user_id,
                tenant_id=current_user.tenant_id,
            ).first()
            if not target:
                raise HTTPException(404, "Utilisateur introuvable")
            reg.dedicated_user_id = data.dedicated_user_id
    if data.reset_device:
        _log.info(
            "reset_device: reg=%s (%s) tenant=%s device_id %r efface, par user=%s",
            reg.id, reg.name, current_user.tenant_id, reg.device_id, current_user.id,
        )
        reg.device_id = None
        reg.is_device_approved = False
        reg.session_token = None
        # Réinitialiser l'appareil vise à libérer complètement la caisse pour
        # un nouvel appareil — une session encore ouverte dessus (oubliée,
        # ou laissée bloquée par une déconnexion prématurée du précédent
        # appareil) la rendait sinon toujours indisponible malgré la
        # réinitialisation (exclue par PosRegister.id.not_in(open_reg_ids)
        # dans _get_or_create_register/cloud_login), obligeant un admin à
        # la fermer séparément via Journal d'audit → Sessions actives.
        _force_close_open_sessions(db, reg, current_user)
    elif data.is_device_approved is not None:
        _log.info(
            "is_device_approved: reg=%s (%s) tenant=%s device_id=%r %s -> %s, par user=%s",
            reg.id, reg.name, current_user.tenant_id, reg.device_id,
            reg.is_device_approved, data.is_device_approved, current_user.id,
        )
        reg.is_device_approved = data.is_device_approved
    db.commit()
    db.refresh(reg)
    d = RegisterRead.model_validate(reg)
    if reg.dedicated_user_id and reg.dedicated_user:
        u = reg.dedicated_user
        d.dedicated_user_name = f"{u.fname} {u.lname}".strip() or u.username
    return d


@router.delete("/{warehouse_id}/registers/{register_id}", response_model=dict)
def delete_register(
    warehouse_id: str,
    register_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.WAREHOUSES_DELETE)),
):
    reg = _get_register_or_404(db, warehouse_id, register_id, current_user.tenant_id)
    # CashierSession.register_id est une FK NOT NULL — un hard-delete plante
    # (IntegrityError → 500) dès que cette caisse a un historique de sessions,
    # ce que le message de confirmation frontend ("l'historique reste
    # conservé") suppose à tort possible. Refuser proprement plutôt que de
    # laisser planter.
    has_history = db.query(CashierSession).filter_by(register_id=register_id).first()
    if has_history:
        raise HTTPException(
            409,
            "Cette caisse a un historique de sessions — impossible de la supprimer "
            "définitivement sans perdre cet historique. Désactivez-la à la place.",
        )
    _billing.close_extra(db, reg.id)
    db.delete(reg)
    db.commit()
    return {"ok": True}


@router.post("/registers/heartbeat")
def register_heartbeat(
    device_id: str = Body(..., embed=True),
    app_version: str | None = Body(None, embed=True),
    app_build: int | None = Body(None, embed=True),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Updates last_seen for the calling device's register (keeps the session slot alive).
    Also records the client's app version/build — seule source permettant à
    l'admin de savoir quels appareils tournent sur une version obsolète."""
    register = db.query(PosRegister).filter(
        PosRegister.tenant_id == current_user.tenant_id,
        PosRegister.device_id == device_id,
    ).first()
    if register:
        register.last_seen = now_local()
        if app_version is not None:
            register.app_version = app_version
        if app_build is not None:
            register.app_build = app_build
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
