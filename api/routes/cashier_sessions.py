from datetime import datetime
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
from api.core.tenant import require_active_plan
from api.core.dt_coerce import now_local
from api.services import audit_service
from api.services.warehouse_helper import resolve_warehouse_id, bind_register_device
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



def _get_or_create_register(
    db: Session, tenant_id: str, device_id: str, name: str,
    force: bool = False, warehouse_id: str | None = None,
    is_admin: bool = False, user_id: str | None = None,
) -> PosRegister | JSONResponse:
    from api.models.AppConfig import AppConfig

    # warehouse_id vient du client (body.warehouse_id) — le valider ici une
    # fois pour toutes protège aussi bien les filtres ci-dessous que la
    # création de caisse plus bas (sinon un warehouse_id d'un autre tenant
    # pourrait finir stocké sur une nouvelle PosRegister, même bug que
    # config.py::_wh_id / restaurant.py create_table/create_menu_item).
    warehouse_id = resolve_warehouse_id(db, tenant_id, warehouse_id) if warehouse_id else None

    if warehouse_id:
        from api.models.Warehouse import Warehouse as _WH
        _wh = db.get(_WH, warehouse_id)
        if _wh and _wh.is_entrepot:
            return JSONResponse(status_code=400, content={
                "detail": "entrepot_no_register",
                "message": "Un entrepôt ne peut pas avoir de caisse — il sert uniquement "
                           "à réceptionner et distribuer du stock.",
            })

    tenant = db.get(Tenant, tenant_id)

    requires_explicit = False
    if warehouse_id and not is_admin:
        wh_cfg = db.query(AppConfig).filter_by(
            tenant_id=tenant_id, warehouse_id=warehouse_id
        ).first()
        if wh_cfg and wh_cfg.business_type in ("restaurant", "hotel"):
            requires_explicit = True

    # 0. Caisse dédiée à cet utilisateur → route directe, peu importe l'appareil.
    #    On met à jour device_id si nécessaire pour que le heartbeat fonctionne.
    if user_id:
        ded_q = db.query(PosRegister).filter(
            PosRegister.tenant_id == tenant_id,
            PosRegister.dedicated_user_id == user_id,
            PosRegister.is_active == True,  # noqa: E712
        )
        if warehouse_id:
            ded_q = ded_q.filter(PosRegister.warehouse_id == warehouse_id)
        dedicated = ded_q.first()
        if dedicated:
            if dedicated.device_id != device_id:
                bind_register_device(dedicated, device_id, reason="dedicated_user_register")
                db.flush()
            return dedicated

    # 1. Cet appareil possède déjà une caisse.
    reg = db.query(PosRegister).filter_by(tenant_id=tenant_id, device_id=device_id).first()
    if reg:
        if not reg.is_active:
            return JSONResponse(status_code=403, content={"detail": "caisse_disabled"})
        # La caisse de cet appareil est réservée à quelqu'un d'autre → ignorer, chercher ailleurs.
        if reg.dedicated_user_id and reg.dedicated_user_id != user_id:
            reg = None
        elif not warehouse_id or reg.warehouse_id == warehouse_id:
            return reg
        else:
            # Appareil déjà lié à un AUTRE dépôt (reg.warehouse_id != warehouse_id).
            # device_id est unique par tenant (contrainte uq_register_tenant_device) —
            # continuer vers l'étape 2 réclamerait un slot libre dans le nouveau
            # dépôt avec ce même device_id, ce qui violerait cette contrainte
            # (IntegrityError) puisque `reg` le porte déjà. Un admin doit
            # explicitement libérer l'appareil (reset_device) avant de le
            # réutiliser ailleurs.
            return JSONResponse(status_code=409, content={
                "detail": "device_bound_elsewhere",
                "message": f"Cet appareil est déjà enregistré pour le dépôt « "
                           f"{reg.warehouse.name if reg.warehouse else '?'} » (caisse « {reg.name} »). "
                           "Un administrateur doit le libérer (Business → Dépôts → Caisses → "
                           "Réinitialiser l'appareil) avant de l'utiliser sur un autre dépôt.",
            })

    # 2. Chercher une caisse libre NON dédiée dans le dépôt demandé.
    # Libre = pas de session ouverte dessus ET jamais réclamée par un autre
    # appareil (device_id NULL) — une caisse déjà liée à un AUTRE appareil
    # ne redevient jamais "libre" simplement parce qu'elle n'a pas de
    # session ouverte en ce moment (ex: fin de service), sinon n'importe
    # quel login pourrait la voler à son propriétaire légitime. Seule une
    # réinitialisation explicite par un admin (reset_device) la remet
    # vraiment à disposition.
    open_reg_ids = (
        db.query(CashierSession.register_id)
        .filter(CashierSession.status == "open")
        .scalar_subquery()
    )
    slot_q = db.query(PosRegister).filter(
        PosRegister.tenant_id == tenant_id,
        PosRegister.is_active == True,  # noqa: E712
        PosRegister.dedicated_user_id.is_(None),
        PosRegister.id.not_in(open_reg_ids),
    )
    if warehouse_id:
        slot_q = slot_q.filter(PosRegister.warehouse_id == warehouse_id)
    if requires_explicit:
        # Mode restaurant/hôtel : exige au contraire une caisse déjà
        # enregistrée manuellement (device_id posé par un admin) — pas une
        # caisse vierge. Cas particulier distinct, voir le commentaire au
        # niveau de requires_explicit plus haut.
        slot_q = slot_q.filter(PosRegister.device_id.isnot(None))
    else:
        slot_q = slot_q.filter(PosRegister.device_id.is_(None))

    free_slot = slot_q.order_by(
        PosRegister.last_seen.is_(None).desc(),
        PosRegister.last_seen.asc(),
    ).first()

    if free_slot:
        bind_register_device(free_slot, device_id, reason="open_session_free_slot")
        db.flush()
        return free_slot

    # 3. Aucun slot libre non dédié — diagnostiquer
    all_q = db.query(PosRegister).filter(
        PosRegister.tenant_id == tenant_id,
        PosRegister.is_active == True,  # noqa: E712
    )
    if warehouse_id:
        all_q = all_q.filter(PosRegister.warehouse_id == warehouse_id)
    all_count = all_q.count()

    non_ded_count = all_q.filter(PosRegister.dedicated_user_id.is_(None)).count()

    if all_count == 0:
        msg = (
            "Aucune caisse configurée pour ce dépôt. Contactez l'administrateur."
            if warehouse_id
            else "Aucune caisse configurée. Contactez l'administrateur."
        )
        return JSONResponse(status_code=409, content={
            "detail":  "no_registers",
            "message": msg,
        })

    if non_ded_count == 0:
        # Toutes les caisses sont dédiées à d'autres utilisateurs
        return JSONResponse(status_code=403, content={
            "detail":  "register_dedicated",
            "message": "Toutes les caisses disponibles sont réservées à d'autres caissiers.",
        })

    if requires_explicit:
        claimed = all_q.filter(
            PosRegister.dedicated_user_id.is_(None),
            PosRegister.device_id.isnot(None),
        ).count()
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
                "current":   all_count,
                "max":       tenant.max_caisses if tenant else all_count,
                "price_htg": price_htg,
                "price_usd": price_usd,
            },
        )

    # 4. force=True : admin a confirmé → créer une caisse supplémentaire non dédiée
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
    warehouse_id: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_OPEN)),
):
    _is_manager = any(r in (current_user.roles or []) for r in ("admin", "manager"))
    reg = db.query(PosRegister).filter_by(
        tenant_id=current_user.tenant_id, device_id=device_id
    ).first()
    if not reg or not reg.is_active:
        return {
            "session": None, "has_register": False,
            "disabled": not reg.is_active if reg else False,
            "device_pending_approval": bool(reg and not reg.is_device_approved and not _is_manager),
        }

    # Chercher la session ouverte de cet utilisateur sur ce registre.
    # On ne filtre PAS sur warehouse_id ici : si la session est ouverte
    # sur un dépôt différent du dépôt actif, on la retourne quand même
    # pour éviter de demander l'ouverture d'une deuxième session fantôme.
    session = (
        db.query(CashierSession)
        .filter_by(register_id=reg.id, cashier_id=current_user.id, status="open")
        .first()
    )

    # Fallback : session ouverte par une autre version du token (même device)
    if not session:
        session = (
            db.query(CashierSession)
            .filter_by(register_id=reg.id, status="open")
            .first()
        )

    warehouse_match = (not warehouse_id) or (reg.warehouse_id == warehouse_id)

    # Dates d'abonnement + caissier dédié — nécessaires pour la vérification offline.
    reg_trial_ends_at   = reg.trial_ends_at.isoformat() if reg.trial_ends_at else None
    reg_sub_ends_at     = reg.subscription_ends_at.isoformat() if reg.subscription_ends_at else None
    reg_dedicated_user  = reg.dedicated_user_id  # peut être None

    if not session:
        return {
            "session":                  None,
            "has_register":             warehouse_match,
            "register_trial_ends_at":   reg_trial_ends_at,
            "register_sub_ends_at":     reg_sub_ends_at,
            "register_dedicated_user":  reg_dedicated_user,
            "device_pending_approval":  not reg.is_device_approved and not _is_manager,
        }

    return {
        "session": {
            "id":              session.id,
            "register_id":     session.register_id,
            "register_name":   reg.name,
            "opening_balance": float(session.opening_balance or 0),
            "opened_at":       session.opened_at,
            "status":          session.status,
        },
        "has_register":                 True,
        "register_trial_ends_at":       reg_trial_ends_at,
        "register_sub_ends_at":         reg_sub_ends_at,
        "register_dedicated_user":      reg_dedicated_user,
    }


@router.post("/open", status_code=201)
def open_session(
    body: OpenSessionBody,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SESSIONS_OPEN)),
    _plan: None = Depends(require_active_plan),
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

    _is_manager = any(r in (current_user.roles or []) for r in ("admin", "manager"))
    if body.force and not _is_manager:
        raise HTTPException(
            403,
            "Aucune caisse disponible. Contactez votre administrateur pour en libérer ou en créer une."
        )

    reg = _get_or_create_register(
        db, current_user.tenant_id, body.device_id, body.register_name,
        force=body.force, warehouse_id=body.warehouse_id,
        is_admin='admin' in (current_user.roles or []),
        user_id=current_user.id,
    )
    # Propagate 402 limit_exceeded, 403 caisse_disabled, or 409 no_registers
    if isinstance(reg, JSONResponse):
        return reg

    # Appareil différent de celui déjà connu pour cette caisse → un admin
    # doit l'approuver avant qu'on puisse transiger dessus (voir
    # bind_register_device). Les admins/managers restent exemptés.
    if not reg.is_device_approved and not _is_manager:
        # Committer la réclamation (device_id + is_device_approved=False)
        # même si la session est refusée : l'appareil doit rester visible en
        # attente d'approbation (Business → Dépôts → Caisses), pas perdu au
        # rollback implicite de la session DB à la fermeture de la requête.
        db.commit()
        return JSONResponse(status_code=403, content={
            "detail": "device_pending_approval",
            "message": "Cet appareil doit être approuvé par un administrateur "
                       "avant de pouvoir ouvrir une caisse.",
        })

    # Vérifier l'abonnement de la caisse — chaque caisse (initiale ou non)
    # a sa propre ligne de facturation (trial_ends_at / subscription_ends_at).
    _now = now_local()
    _sub_end   = reg.subscription_ends_at
    _trial_end = reg.trial_ends_at
    _has_sub   = _sub_end   is not None and _sub_end   > _now
    _has_trial = _trial_end is not None and _trial_end > _now

    if not _has_sub and not _has_trial and reg.is_initial:
        # Caisse initiale sans trial/sub → réparer depuis le trial du tenant
        # (cas VPS où trial_ends_at était NULL car ancienne colonne DATETIME)
        _tenant = db.get(Tenant, current_user.tenant_id)
        if _tenant and _tenant.trial_ends_at:
            _t = _tenant.trial_ends_at
            if _t > _now:
                reg.trial_ends_at = _t
                db.flush()
                _has_trial = True

    if not _has_sub and not _has_trial:
        return JSONResponse(status_code=402, content={
            "detail":  "register_no_subscription",
            "message": "Cette caisse n'a pas d'abonnement actif. "
                       "Payez l'abonnement depuis la page Abonnement pour l'utiliser.",
        })

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
        opened_at=now_local(),
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

    now   = now_local()
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

    closed_at = now_local()
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

    closed_at = now_local()
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
