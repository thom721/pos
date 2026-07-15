from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.database import get_db
from api.models.User import User
from api.models.CashierSession import CashierSession
from api.models.PosRegister import PosRegister
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.services import audit_service

router = APIRouter(prefix="/api/sessions", tags=["Cashier Sessions"])


class OpenSessionBody(BaseModel):
    device_id: str
    register_name: str = "Caisse"
    opening_balance: float = 0.0


class CloseSessionBody(BaseModel):
    closing_balance: float


def _get_or_create_register(db: Session, tenant_id: str, device_id: str, name: str) -> PosRegister:
    reg = db.query(PosRegister).filter_by(tenant_id=tenant_id, device_id=device_id).first()
    if not reg:
        reg = PosRegister(tenant_id=tenant_id, device_id=device_id, name=name)
        db.add(reg)
        db.flush()
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
    if not reg:
        return {"session": None}

    session = (
        db.query(CashierSession)
        .filter_by(register_id=reg.id, cashier_id=current_user.id, status="open")
        .first()
    )
    if not session:
        return {"session": None}

    return {
        "session": {
            "id":              session.id,
            "register_id":     session.register_id,
            "register_name":   reg.name,
            "opening_balance": float(session.opening_balance or 0),
            "opened_at":       session.opened_at,
            "status":          session.status,
        }
    }


@router.post("/open", status_code=201)
def open_session(
    body: OpenSessionBody,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_OPEN)),
):
    existing = (
        db.query(CashierSession)
        .join(PosRegister, CashierSession.register_id == PosRegister.id)
        .filter(
            PosRegister.device_id == body.device_id,
            CashierSession.tenant_id == current_user.tenant_id,
            CashierSession.cashier_id == current_user.id,
            CashierSession.status == "open",
        )
        .first()
    )
    if existing:
        raise HTTPException(400, "Une session est déjà ouverte sur cet appareil")

    reg = _get_or_create_register(
        db, current_user.tenant_id, body.device_id, body.register_name
    )

    session = CashierSession(
        tenant_id=current_user.tenant_id,
        register_id=reg.id,
        cashier_id=current_user.id,
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
        detail={"opening_balance": body.opening_balance, "device_id": body.device_id},
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

    session.closed_at = datetime.now(timezone.utc)
    session.closing_balance = body.closing_balance
    session.status = "closed"

    audit_service.log(
        db,
        user_id=current_user.id,
        tenant_id=current_user.tenant_id,
        action="CLOSE",
        resource_type="cashier_session",
        resource_id=session.id,
        detail={"closing_balance": body.closing_balance},
    )

    db.commit()
    return {"message": "Session fermée"}


@router.get("/")
def list_sessions(
    page: int = 1,
    limit: int = 20,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_READ)),
):
    from sqlalchemy import desc
    q = db.query(CashierSession).filter_by(tenant_id=current_user.tenant_id)
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
