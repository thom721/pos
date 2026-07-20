from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from api.database import get_db
from api.models.User import User
from api.models.CashierSession import CashierSession
from api.models.Payment import Payment
from api.models.ReturnRecord import ReturnRecord
from api.models.PosRegister import PosRegister
from api.models.Tenant import Tenant
from api.models.PlatformConfig import PlatformConfig
from api.dependencies.auth import require_permission
from api.core.permissions import P, has_permission as _has_perm
from api.services import audit_service
from api.services import billing_extra_service as _billing

router = APIRouter(prefix="/api/sessions", tags=["Cashier Sessions"])


class OpenSessionBody(BaseModel):
    device_id: str
    register_name: str = "Caisse"
    opening_balance: float = 0.0
    force: bool = False  # bypass caisse limit after user confirmation
    warehouse_id: str | None = None  # si fourni, réassigne la caisse à ce dépôt


class CloseSessionBody(BaseModel):
    closing_balance: float


def _compute_reconciliation(db: Session, session: CashierSession, closed_at: datetime) -> dict:
    """Query payments and refunds within the session window to compute reconciliation."""
    since = session.opened_at
    until = closed_at
    tid   = session.tenant_id
    uid   = session.cashier_id

    def _sales_by_method(method: str) -> float:
        row = db.query(func.coalesce(func.sum(Payment.amount), 0)).filter(
            Payment.tenant_id     == tid,
            Payment.user_id       == uid,
            Payment.reference_type == "SALE",
            Payment.method        == method,
            Payment.created_at    >= since,
            Payment.created_at    <= until,
        ).scalar()
        return float(row or 0)

    cash   = _sales_by_method("cash")
    card   = _sales_by_method("card")
    mobile = _sales_by_method("mobile")
    bank   = _sales_by_method("bank")

    refunds = float(db.query(func.coalesce(func.sum(ReturnRecord.refund_amount), 0)).filter(
        ReturnRecord.tenant_id   == tid,
        ReturnRecord.user_id     == uid,
        ReturnRecord.return_type == "sale",
        ReturnRecord.created_at  >= since,
        ReturnRecord.created_at  <= until,
    ).scalar() or 0)

    opening  = float(session.opening_balance or 0)
    expected = opening + cash - refunds

    return {
        "total_cash_sales":         cash,
        "total_card_sales":         card,
        "total_mobile_sales":       mobile,
        "total_bank_sales":         bank,
        "total_refunds_cash":       refunds,
        "expected_closing_balance": expected,
    }


_SLOT_IDLE_MINUTES = 5   # slot considered free after 5 min without heartbeat


def _get_or_create_register(
    db: Session, tenant_id: str, device_id: str, name: str,
    force: bool = False, warehouse_id: str | None = None,
) -> PosRegister | JSONResponse:
    from api.models.AppConfig import AppConfig

    tenant = db.get(Tenant, tenant_id)

    # Restaurant/hotel require devices to be explicitly registered in Business → Caisses.
    # Auto-claiming unclaimed slots is only allowed for commerce-type warehouses.
    requires_explicit = False
    if warehouse_id:
        wh_cfg = db.query(AppConfig).filter_by(
            tenant_id=tenant_id, warehouse_id=warehouse_id
        ).first()
        if wh_cfg and wh_cfg.business_type in ("restaurant", "hotel"):
            requires_explicit = True

    # 1. Cet appareil possède déjà une caisse → réutiliser si elle appartient au bon dépôt
    reg = db.query(PosRegister).filter_by(tenant_id=tenant_id, device_id=device_id).first()
    if reg:
        if not reg.is_active:
            return JSONResponse(status_code=403, content={"detail": "caisse_disabled"})
        if not warehouse_id or reg.warehouse_id == warehouse_id:
            return reg
        # La caisse existante appartient à un autre dépôt → chercher un slot dans le bon dépôt

    # 2. Chercher une caisse libre dans le dépôt demandé (sans session active)
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=_SLOT_IDLE_MINUTES)
    slot_q = db.query(PosRegister).filter(
        PosRegister.tenant_id == tenant_id,
        PosRegister.is_active == True,  # noqa: E712
        or_(PosRegister.last_seen.is_(None), PosRegister.last_seen < cutoff),
    )
    if warehouse_id:
        slot_q = slot_q.filter(PosRegister.warehouse_id == warehouse_id)
    if requires_explicit:
        # Only re-claim previously registered devices; don't auto-assign unclaimed slots
        slot_q = slot_q.filter(PosRegister.device_id.isnot(None))

    free_slot = slot_q.order_by(
        PosRegister.last_seen.is_(None).desc(),
        PosRegister.last_seen.asc(),
    ).first()

    if free_slot:
        free_slot.device_id = device_id
        db.flush()
        return free_slot

    # 3. Aucun slot libre dans ce dépôt — vérifier la limite
    count_q = db.query(PosRegister).filter(
        PosRegister.tenant_id == tenant_id,
        PosRegister.is_active == True,  # noqa: E712
    )
    if warehouse_id:
        count_q = count_q.filter(PosRegister.warehouse_id == warehouse_id)
    active_count = count_q.count()

    if active_count == 0:
        msg = (
            "Aucune caisse configurée pour ce dépôt. Contactez l'administrateur."
            if warehouse_id
            else "Aucune caisse configurée. Contactez l'administrateur."
        )
        return JSONResponse(status_code=409, content={
            "detail":  "no_registers",
            "message": msg,
        })

    # Restaurant/hotel: registers exist but none have been claimed by a device yet
    if requires_explicit:
        claimed = count_q.filter(PosRegister.device_id.isnot(None)).count()
        if claimed == 0:
            return JSONResponse(status_code=409, content={
                "detail":  "no_registered_devices",
                "message": "Aucun appareil n'est enregistré comme caisse pour ce dépôt. "
                           "Enregistrez d'abord un appareil dans la section Business → Caisses.",
            })

    if not force:
        cfg = db.query(PlatformConfig).first()
        price_htg = float(cfg.price_per_extra_caisse_htg) if cfg else 500.0
        price_usd = float(cfg.price_per_extra_caisse_usd) if cfg else 4.0
        return JSONResponse(
            status_code=402,
            content={
                "detail":    "limit_exceeded",
                "resource":  "caisse",
                "current":   active_count,
                "max":       tenant.max_caisses if tenant else active_count,
                "price_htg": price_htg,
                "price_usd": price_usd,
            },
        )

    # 4. force=True : admin a confirmé → créer une caisse supplémentaire
    reg = PosRegister(
        tenant_id=tenant_id, device_id=device_id, name=name,
        warehouse_id=warehouse_id,
    )
    db.add(reg)
    db.flush()
    if tenant:
        _billing.record_extra(db, tenant_id, "caisse", reg.id)
    return reg


@router.get("/current")
def get_current_session(
    device_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_OPEN)),
):
    reg = db.query(PosRegister).filter_by(
        tenant_id=current_user.tenant_id, device_id=device_id
    ).first()
    if not reg or not reg.is_active:
        return {"session": None, "has_register": False, "disabled": not reg.is_active if reg else False}

    session = (
        db.query(CashierSession)
        .filter_by(register_id=reg.id, cashier_id=current_user.id, status="open")
        .first()
    )
    if not session:
        return {"session": None, "has_register": True}

    return {
        "session": {
            "id":              session.id,
            "register_id":     session.register_id,
            "register_name":   reg.name,
            "opening_balance": float(session.opening_balance or 0),
            "opened_at":       session.opened_at,
            "status":          session.status,
        },
        "has_register": True,
    }


@router.post("/open", status_code=201)
def open_session(
    body: OpenSessionBody,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_OPEN)),
):
    existing = (
        db.query(CashierSession)
        .filter(
            CashierSession.tenant_id == current_user.tenant_id,
            CashierSession.cashier_id == current_user.id,
            CashierSession.status == "open",
        )
        .first()
    )
    if existing:
        raise HTTPException(400, "Une session est déjà ouverte. Fermez la session existante avant d'en ouvrir une nouvelle.")

    reg = _get_or_create_register(
        db, current_user.tenant_id, body.device_id, body.register_name,
        force=body.force, warehouse_id=body.warehouse_id,
    )
    # Propagate 402 limit_exceeded, 403 caisse_disabled, or 409 no_registers
    if isinstance(reg, JSONResponse):
        return reg

    # Block if the linked warehouse is disabled
    if reg.warehouse_id:
        from api.models.Warehouse import Warehouse as _WH
        wh = db.get(_WH, reg.warehouse_id)
        if wh and not wh.is_active:
            raise HTTPException(403, "Le dépôt associé à cette caisse est désactivé")

    session = CashierSession(
        tenant_id=current_user.tenant_id,
        register_id=reg.id,
        cashier_id=current_user.id,
        warehouse_id=reg.warehouse_id,   # hérite du dépôt de la caisse
        opened_at=datetime.now(timezone.utc),
        opening_balance=body.opening_balance,
        status="open",
    )
    db.add(session)

    audit_service.log(
        db,
        user_id=current_user.id,
        tenant_id=current_user.tenant_id,
        action="OPEN",
        resource_type="cashier_session",
        resource_id=session.id,
        detail={
            "opening_balance": body.opening_balance,
            "device_id": body.device_id,
            "opened_at": session.opened_at.isoformat(),
        },
    )

    db.commit()
    db.refresh(session)

    return {
        "message": "Session ouverte",
        "session": {
            "id":              session.id,
            "register_id":     reg.id,
            "register_name":   reg.name,
            "opening_balance": float(session.opening_balance or 0),
            "opened_at":       session.opened_at,
            "status":          session.status,
        },
    }


@router.get("/open-sessions")
def list_open_sessions(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_READ)),
):
    if not any(r in (current_user.roles or []) for r in ("admin", "manager")):
        raise HTTPException(403, "Accès réservé aux administrateurs")

    sessions = (
        db.query(CashierSession)
        .filter_by(tenant_id=current_user.tenant_id, status="open")
        .order_by(CashierSession.opened_at)
        .all()
    )

    user_cache: dict[str, str] = {}

    def _name(uid: str) -> str:
        if uid not in user_cache:
            u = db.get(User, uid)
            user_cache[uid] = f"{u.fname} {u.lname}".strip() if u else uid
        return user_cache[uid]

    reg_cache: dict[str, str] = {}

    def _reg_name(rid: str) -> str:
        if rid not in reg_cache:
            r = db.get(PosRegister, rid)
            reg_cache[rid] = r.name if r else rid
        return reg_cache[rid]

    return [
        {
            "id":               s.id,
            "cashier_id":       s.cashier_id,
            "cashier_name":     _name(s.cashier_id),
            "register_name":    _reg_name(s.register_id),
            "opening_balance":  float(s.opening_balance or 0),
            "opened_at":        s.opened_at.isoformat() if s.opened_at else None,
        }
        for s in sessions
    ]


@router.get("/{session_id}/summary")
def session_summary(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_READ)),
):
    """Return live reconciliation data for an open session (used by close dialog)."""
    session = db.get(CashierSession, session_id)
    if not session or session.tenant_id != current_user.tenant_id:
        raise HTTPException(404, "Session introuvable")

    now   = datetime.now(timezone.utc)
    recon = _compute_reconciliation(db, session, now)
    return {
        "opening_balance":          float(session.opening_balance or 0),
        "total_cash_sales":         recon["total_cash_sales"],
        "total_card_sales":         recon["total_card_sales"],
        "total_mobile_sales":       recon["total_mobile_sales"],
        "total_bank_sales":         recon["total_bank_sales"],
        "total_refunds_cash":       recon["total_refunds_cash"],
        "expected_closing_balance": recon["expected_closing_balance"],
    }


@router.post("/{session_id}/close")
def close_session(
    session_id: str,
    body: CloseSessionBody,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_CLOSE)),
):
    session = db.get(CashierSession, session_id)
    if not session or session.tenant_id != current_user.tenant_id:
        raise HTTPException(404, "Session introuvable")
    if session.status != "open":
        raise HTTPException(400, "Session déjà fermée")
    if session.cashier_id != current_user.id:
        # Only the owning cashier or an admin can close the session
        if not any(r in (current_user.roles or []) for r in ("admin", "manager")):
            raise HTTPException(403, "Vous ne pouvez pas fermer la session d'un autre caissier")

    closed_at = datetime.now(timezone.utc)
    recon     = _compute_reconciliation(db, session, closed_at)

    session.closed_at                = closed_at
    session.closing_balance          = body.closing_balance
    session.status                   = "closed"
    session.total_cash_sales         = recon["total_cash_sales"]
    session.total_card_sales         = recon["total_card_sales"]
    session.total_mobile_sales       = recon["total_mobile_sales"]
    session.total_bank_sales         = recon["total_bank_sales"]
    session.total_refunds_cash       = recon["total_refunds_cash"]
    session.expected_closing_balance = recon["expected_closing_balance"]
    session.cash_difference          = body.closing_balance - recon["expected_closing_balance"]

    audit_service.log(
        db,
        user_id=current_user.id,
        tenant_id=current_user.tenant_id,
        action="CLOSE",
        resource_type="cashier_session",
        resource_id=session.id,
        detail={
            "closing_balance": body.closing_balance,
            "closed_at": closed_at.isoformat(),
            "cash_difference": float(session.cash_difference or 0),
        },
    )

    db.commit()
    return {
        "message":                  "Session fermée",
        "opening_balance":          float(session.opening_balance or 0),
        "closing_balance":          float(session.closing_balance or 0),
        "total_cash_sales":         float(session.total_cash_sales or 0),
        "total_card_sales":         float(session.total_card_sales or 0),
        "total_mobile_sales":       float(session.total_mobile_sales or 0),
        "total_bank_sales":         float(session.total_bank_sales or 0),
        "total_refunds_cash":       float(session.total_refunds_cash or 0),
        "expected_closing_balance": float(session.expected_closing_balance or 0),
        "cash_difference":          float(session.cash_difference or 0),
    }


@router.post("/{session_id}/force-close")
def force_close_session(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_CLOSE)),
):
    if not any(r in (current_user.roles or []) for r in ("admin", "manager")):
        raise HTTPException(403, "Accès réservé aux administrateurs")

    session = db.get(CashierSession, session_id)
    if not session or session.tenant_id != current_user.tenant_id:
        raise HTTPException(404, "Session introuvable")
    if session.status != "open":
        raise HTTPException(400, "Session déjà fermée")

    closed_at = datetime.now(timezone.utc)
    recon     = _compute_reconciliation(db, session, closed_at)

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

    # Free the register slot — clears JWT sid so the device is kicked out
    reg = db.get(PosRegister, session.register_id)
    if reg:
        reg.session_token = None

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
        },
    )

    db.commit()
    return {"message": "Session fermée de force", "closed_at": closed_at.isoformat()}


@router.get("/")
def list_sessions(
    page: int = 1,
    limit: int = 20,
    warehouse_id: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_READ)),
):
    from sqlalchemy import desc
    can_see_all = _has_perm(
        current_user.permissions or [],
        current_user.roles or [],
        P.REPORTS_READ_ALL,
    )
    q = db.query(CashierSession).filter(CashierSession.tenant_id == current_user.tenant_id)
    if not can_see_all:
        q = q.filter(CashierSession.cashier_id == current_user.id)
    if warehouse_id:
        q = q.filter(CashierSession.warehouse_id == warehouse_id)
    total = q.count()
    items = q.order_by(desc(CashierSession.created_at)).offset((page - 1) * limit).limit(limit).all()

    from api.models.User import User as UserModel
    user_cache: dict[str, str] = {}

    def _name(uid):
        if uid not in user_cache:
            u = db.get(UserModel, uid)
            user_cache[uid] = f"{u.fname} {u.lname}".strip() if u else uid
        return user_cache[uid]

    reg_cache: dict[str, str] = {}

    def _reg_name(rid):
        if rid not in reg_cache:
            r = db.get(PosRegister, rid)
            reg_cache[rid] = r.name if r else rid
        return reg_cache[rid]

    return {
        "total": total,
        "page": page,
        "data": [
            {
                "id":              s.id,
                "cashier_id":      s.cashier_id,
                "cashier_name":    _name(s.cashier_id),
                "register_name":   _reg_name(s.register_id),
                "status":          s.status,
                "opening_balance": float(s.opening_balance or 0),
                "closing_balance": float(s.closing_balance or 0) if s.closing_balance else None,
                "opened_at":       s.opened_at,
                "closed_at":       s.closed_at,
            }
            for s in items
        ],
    }
