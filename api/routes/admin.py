"""
Super-admin panel API — platform-owner only.
All endpoints are protected by require_superadmin (superadmin JWT).
"""
import logging
from datetime import datetime, timedelta, timezone
from math import ceil

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from api.core.billing_crypto import try_decrypt_date, encrypt_date
from api.core.config import settings
from api.core.security import create_access_token
from api.core.superadmin import require_superadmin
from api.database import get_db
from api.models.BillingPayment import BillingPayment
from api.models.PlatformConfig import PlatformConfig
from api.models.Tenant import Tenant
from api.models.PosRegister import PosRegister
from api.models.Warehouse import Warehouse

router = APIRouter(prefix="/api/admin", tags=["SuperAdmin"])
_log = logging.getLogger("pos.admin")


# ── Pydantic schemas ────────────────────────────────────────────────────────

class AdminLogin(BaseModel):
    email: str
    password: str


class CreateTenantPayload(BaseModel):
    business_name: str
    owner_email:   str
    password:      str
    phone:         str | None = None
    type:          str = "shared"          # 'shared' | 'selfhosted'
    self_hosted_url: str | None = None
    max_caisses:   int = 1
    max_depots:    int = 1
    can_manage_tenants: bool = False


class TenantPatch(BaseModel):
    status: str | None = None           # 'trial' | 'active' | 'suspended'
    extra_trial_days: int | None = None  # extend trial by N days
    type: str | None = None             # 'shared' | 'selfhosted'
    self_hosted_url: str | None = None
    max_caisses: int | None = None
    max_depots:  int | None = None
    can_manage_tenants: bool | None = None


class ManualActivatePayload(BaseModel):
    amount: float
    currency: str = "HTG"
    months: int = 1                # durée en mois
    method: str = "manual"         # manual | moncash | natcash
    reference: str | None = None
    description: str | None = None


class ConfirmPaymentPayload(BaseModel):
    months: int | None = None  # None = use months stored on the payment


class PlatformConfigUpdate(BaseModel):
    moncash_number: str | None = None
    natcash_number: str | None = None
    monthly_price_htg: float | None = None
    monthly_price_usd: float | None = None
    stripe_price_id: str | None = None
    trial_days: int | None = None
    support_email: str | None = None
    support_whatsapp: str | None = None
    moncash_mode: str | None = None   # 'manual' | 'api'
    natcash_mode: str | None = None   # 'manual' | 'api'
    price_per_extra_caisse_htg: float | None = None
    price_per_extra_caisse_usd: float | None = None
    price_per_extra_depot_htg:  float | None = None
    price_per_extra_depot_usd:  float | None = None


# ── Internal helpers ────────────────────────────────────────────────────────

def _next_invoice_number(db: Session, tenant_id: str) -> str:
    year = datetime.now(timezone.utc).year
    prefix = f"INV-{year}-"
    count = db.query(BillingPayment).filter(
        BillingPayment.tenant_id == tenant_id,
        BillingPayment.invoice_number.like(f"{prefix}%"),
    ).count()
    return f"{prefix}{count + 1:04d}"


def _activate_tenant(db: Session, tenant: Tenant, months: int = 1) -> None:
    now = datetime.now(timezone.utc)
    # Si déjà actif et pas encore expiré, prolonger depuis la fin actuelle
    current_end = getattr(tenant, "subscription_ends_at", None)
    if current_end:
        if current_end.tzinfo is None:
            current_end = current_end.replace(tzinfo=timezone.utc)
        base = current_end if current_end > now else now
    else:
        base = now
    tenant.status = "active"
    tenant.subscription_started_at = tenant.subscription_started_at or now
    tenant.subscription_ends_at    = base + timedelta(days=30 * months)
    db.commit()
    _log.info("Tenant activé : %s (%s) — %d mois → fin %s",
              tenant.slug, tenant.id, months, tenant.subscription_ends_at.date())


def _days_left(tenant: Tenant) -> int | None:
    if tenant.trial_ends_at is None:
        return None
    now = datetime.now(timezone.utc)
    trial_end = tenant.trial_ends_at
    if trial_end.tzinfo is None:
        trial_end = trial_end.replace(tzinfo=timezone.utc)
    return max(0, ceil((trial_end - now).total_seconds() / 86400))


def _serialize_payment(p: BillingPayment, business_name: str) -> dict:
    period_start = try_decrypt_date(p.period_start, p.tenant_id)
    period_end   = try_decrypt_date(p.period_end,   p.tenant_id)
    return {
        "id":             p.id,
        "tenant_id":      p.tenant_id,
        "business_name":  business_name,
        "invoice_number": p.invoice_number,
        "method":         p.method,
        "amount":         float(p.amount),
        "currency":       p.currency,
        "status":         p.status,
        "reference":      p.reference,
        "description":    p.description,
        "paid_at":        p.paid_at.isoformat() if p.paid_at else None,
        "period_start":   period_start.isoformat() if period_start else None,
        "period_end":     period_end.isoformat()   if period_end   else None,
        "created_at":     p.created_at.isoformat() if p.created_at else None,
    }


def _get_platform_config(db: Session) -> PlatformConfig:
    cfg = db.query(PlatformConfig).first()
    if not cfg:
        cfg = PlatformConfig()
        db.add(cfg)
        db.commit()
        db.refresh(cfg)
    return cfg


# ── Auth ────────────────────────────────────────────────────────────────────

@router.post("/auth")
def admin_login(payload: AdminLogin):
    from pwdlib import PasswordHash as _PH
    from jose import jwt as _jwt
    from datetime import datetime as _dt

    email_ok = settings.ADMIN_EMAIL and payload.email == settings.ADMIN_EMAIL
    hash_ok  = (
        bool(settings.ADMIN_PASSWORD_HASH)
        and _PH.recommended().verify(payload.password, settings.ADMIN_PASSWORD_HASH)
    )
    if not (email_ok and hash_ok):
        raise HTTPException(status_code=403, detail="Email ou mot de passe invalide")

    token_24h = _jwt.encode(
        {"sub": "superadmin", "role": "superadmin",
         "exp": _dt.utcnow() + timedelta(hours=24)},
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )
    return {"access_token": token_24h, "token_type": "bearer"}


# ── Stats ───────────────────────────────────────────────────────────────────

@router.get("/stats")
def platform_stats(
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    tenants = db.query(Tenant).filter(Tenant.is_local == False).all()  # noqa: E712
    total_tenants = len(tenants)
    active    = sum(1 for t in tenants if t.status == "active")
    trial     = sum(1 for t in tenants if t.status == "trial")
    suspended = sum(1 for t in tenants if t.status == "suspended")

    payments = db.query(BillingPayment).all()
    total_payments = len(payments)

    mrr_usd = sum(
        float(p.amount) for p in payments
        if p.currency.upper() == "USD" and p.status == "paid"
    )
    mrr_htg = sum(
        float(p.amount) for p in payments
        if p.currency.upper() == "HTG" and p.status == "paid"
    )

    return {
        "total_tenants":  total_tenants,
        "active":         active,
        "trial":          trial,
        "suspended":      suspended,
        "total_payments": total_payments,
        "mrr_usd":        round(mrr_usd, 2),
        "mrr_htg":        round(mrr_htg, 2),
    }


# ── Tenants list ────────────────────────────────────────────────────────────

@router.get("/tenants")
def list_tenants(
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    tenants = (
        db.query(Tenant)
        .filter(Tenant.is_local == False)  # noqa: E712
        .order_by(Tenant.created_at.desc())
        .all()
    )

    # Batch-count registers and warehouses for all tenants in 2 queries
    tenant_ids = [t.id for t in tenants]

    register_counts = {
        row.tenant_id: row.cnt
        for row in db.query(
            PosRegister.tenant_id,
            func.count(PosRegister.id).label("cnt"),
        ).filter(PosRegister.tenant_id.in_(tenant_ids))
         .group_by(PosRegister.tenant_id)
         .all()
    }

    depot_counts = {
        row.tenant_id: row.cnt
        for row in db.query(
            Warehouse.tenant_id,
            func.count(Warehouse.id).label("cnt"),
        ).filter(Warehouse.tenant_id.in_(tenant_ids))
         .group_by(Warehouse.tenant_id)
         .all()
    }

    result = []
    for t in tenants:
        # payment stats
        payments = db.query(BillingPayment).filter(
            BillingPayment.tenant_id == t.id
        ).all()
        payment_count = len(payments)
        last_payment_at = None
        if payments:
            paid_ats = [p.paid_at for p in payments if p.paid_at]
            if paid_ats:
                last_payment_at = max(paid_ats).isoformat()

        result.append({
            "id":                     t.id,
            "slug":                   t.slug,
            "business_name":          t.business_name,
            "owner_email":            t.owner_email,
            "phone":                  t.phone,
            "status":                 t.status,
            "type":                   t.type,
            "self_hosted_url":        t.self_hosted_url,
            "max_caisses":            t.max_caisses,
            "max_depots":             getattr(t, "max_depots", 1),
            "can_manage_tenants":     t.can_manage_tenants,
            "days_left":              _days_left(t),
            "trial_ends_at":          t.trial_ends_at.isoformat() if t.trial_ends_at else None,
            "subscription_started_at": t.subscription_started_at.isoformat() if t.subscription_started_at else None,
            "created_at":             t.created_at.isoformat() if t.created_at else None,
            "payment_count":          payment_count,
            "last_payment_at":        last_payment_at,
            "has_stripe":             bool(t.stripe_customer_id or t.stripe_subscription_id),
            "register_count":         register_counts.get(t.id, 0),
            "depot_count":            depot_counts.get(t.id, 0),
        })

    return result


# ── Create tenant ───────────────────────────────────────────────────────────

@router.post("/tenants", status_code=201)
def create_tenant(
    body: CreateTenantPayload,
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    """Create a new cloud tenant with optional self-hosted configuration."""
    import re
    import secrets
    from pwdlib import PasswordHash as _PH
    from api.models.User import User
    from api.core.config import settings as _settings

    # Validate type
    if body.type not in ("shared", "selfhosted"):
        raise HTTPException(status_code=400, detail="type doit être 'shared' ou 'selfhosted'")
    if body.type == "selfhosted" and not body.self_hosted_url:
        raise HTTPException(status_code=400, detail="self_hosted_url est requis pour un tenant selfhosted")

    # Unique slug from business name
    base_slug = re.sub(r"[^a-z0-9]+", "-", body.business_name.lower()).strip("-") or "tenant"
    slug = base_slug
    attempt = 0
    while db.query(Tenant).filter(Tenant.slug == slug).first():
        attempt += 1
        slug = f"{base_slug}-{attempt}"

    if db.query(Tenant).filter(Tenant.owner_email == body.owner_email).first():
        raise HTTPException(status_code=400, detail="Cet email est déjà associé à un tenant")

    cfg = _get_platform_config(db)
    trial_days = cfg.trial_days or 30

    now = datetime.now(timezone.utc)
    tenant = Tenant(
        slug=slug,
        business_name=body.business_name,
        owner_email=body.owner_email,
        phone=body.phone,
        status="trial",
        trial_ends_at=now + timedelta(days=trial_days),
        is_local=False,
        type=body.type,
        self_hosted_url=body.self_hosted_url,
        max_caisses=body.max_caisses,
        max_depots=body.max_depots,
        can_manage_tenants=body.can_manage_tenants,
    )
    db.add(tenant)
    db.flush()

    # Create owner user account
    username = body.owner_email.split("@")[0]
    while db.query(User).filter(User.username == username).first():
        username = f"{username}{secrets.token_hex(2)}"

    owner_user = User(
        tenant_id=tenant.id,
        fname=body.business_name,
        lname="",
        username=username,
        phone=body.phone or f"+000{secrets.token_hex(4)}",
        email=body.owner_email,
        roles=["owner", "manager", "cashier"],
        permissions=[],
        password=_PH.recommended().hash(body.password),
        must_change_password=False,
    )
    db.add(owner_user)
    db.commit()
    db.refresh(tenant)

    _log.info("Tenant créé: %s (%s) type=%s", tenant.slug, tenant.id, tenant.type)

    return {
        "id":                  tenant.id,
        "slug":                tenant.slug,
        "business_name":       tenant.business_name,
        "owner_email":         tenant.owner_email,
        "status":              tenant.status,
        "type":                tenant.type,
        "self_hosted_url":     tenant.self_hosted_url,
        "max_caisses":         tenant.max_caisses,
        "can_manage_tenants":  tenant.can_manage_tenants,
        "trial_ends_at":       tenant.trial_ends_at.isoformat() if tenant.trial_ends_at else None,
    }


# ── Tenant detail ───────────────────────────────────────────────────────────

@router.get("/tenants/{tenant_id}")
def get_tenant(
    tenant_id: str,
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    t = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Tenant introuvable")

    payments = (
        db.query(BillingPayment)
        .filter(BillingPayment.tenant_id == tenant_id)
        .order_by(BillingPayment.created_at.desc())
        .all()
    )

    return {
        "id":                     t.id,
        "slug":                   t.slug,
        "business_name":          t.business_name,
        "owner_email":            t.owner_email,
        "phone":                  t.phone,
        "status":                 t.status,
        "type":                   t.type,
        "self_hosted_url":        t.self_hosted_url,
        "max_caisses":            t.max_caisses,
        "can_manage_tenants":     t.can_manage_tenants,
        "days_left":              _days_left(t),
        "trial_ends_at":          t.trial_ends_at.isoformat() if t.trial_ends_at else None,
        "subscription_started_at": t.subscription_started_at.isoformat() if t.subscription_started_at else None,
        "created_at":             t.created_at.isoformat() if t.created_at else None,
        "stripe_customer_id":     t.stripe_customer_id,
        "stripe_subscription_id": t.stripe_subscription_id,
        "has_stripe":             bool(t.stripe_customer_id or t.stripe_subscription_id),
        "payments":               [_serialize_payment(p, t.business_name) for p in payments],
    }


# ── Patch tenant ────────────────────────────────────────────────────────────

@router.patch("/tenants/{tenant_id}")
def patch_tenant(
    tenant_id: str,
    body: TenantPatch,
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    t = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Tenant introuvable")

    if body.status is not None:
        valid = {"trial", "active", "suspended", "expired"}
        if body.status not in valid:
            raise HTTPException(status_code=400, detail=f"Statut invalide. Valeurs: {valid}")
        t.status = body.status

    if body.extra_trial_days is not None and body.extra_trial_days > 0:
        base = t.trial_ends_at or datetime.now(timezone.utc)
        if base.tzinfo is None:
            base = base.replace(tzinfo=timezone.utc)
        t.trial_ends_at = base + timedelta(days=body.extra_trial_days)

    if body.type is not None:
        if body.type not in ("shared", "selfhosted"):
            raise HTTPException(status_code=400, detail="type doit être 'shared' ou 'selfhosted'")
        t.type = body.type

    if body.self_hosted_url is not None:
        t.self_hosted_url = body.self_hosted_url or None

    if body.max_caisses is not None:
        if body.max_caisses < 1:
            raise HTTPException(status_code=400, detail="max_caisses doit être >= 1")
        t.max_caisses = body.max_caisses

    if body.max_depots is not None:
        if body.max_depots < 1:
            raise HTTPException(status_code=400, detail="max_depots doit être >= 1")
        t.max_depots = body.max_depots

    if body.can_manage_tenants is not None:
        t.can_manage_tenants = body.can_manage_tenants

    db.commit()
    db.refresh(t)
    return {
        "id":                 t.id,
        "status":             t.status,
        "type":               t.type,
        "self_hosted_url":    t.self_hosted_url,
        "max_caisses":        t.max_caisses,
        "max_depots":         getattr(t, "max_depots", 1),
        "can_manage_tenants": t.can_manage_tenants,
        "trial_ends_at":      t.trial_ends_at.isoformat() if t.trial_ends_at else None,
        "days_left":          _days_left(t),
    }


# ── Manual activation ───────────────────────────────────────────────────────

@router.post("/tenants/{tenant_id}/activate")
def manual_activate_tenant(
    tenant_id: str,
    body: ManualActivatePayload,
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    t = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Tenant introuvable")

    now = datetime.now(timezone.utc)
    period_start = now
    period_end   = now + timedelta(days=30)

    months       = max(1, body.months)
    period_end   = now + timedelta(days=30 * months)

    payment = BillingPayment(
        tenant_id=tenant_id,
        invoice_number=_next_invoice_number(db, tenant_id),
        method=body.method,
        amount=body.amount,
        currency=body.currency,
        status="paid",
        reference=body.reference,
        description=body.description or f"Activation manuelle ({months} mois) — Admin POS Connect",
        paid_at=now,
        period_start=encrypt_date(period_start, tenant_id),
        period_end=encrypt_date(period_end, tenant_id),
    )
    db.add(payment)
    db.flush()

    _activate_tenant(db, t, months=months)

    return {
        "status":               "ok",
        "tenant":               t.slug,
        "new_status":           t.status,
        "invoice_number":       payment.invoice_number,
        "subscription_ends_at": t.subscription_ends_at.isoformat(),
    }


# ── Confirm pending payment ──────────────────────────────────────────────────

@router.patch("/payments/{payment_id}/confirm")
def confirm_payment(
    payment_id: str,
    body: ConfirmPaymentPayload,
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    """
    Confirms a pending BillingPayment (MonCash/NatCash submitted by the tenant).
    Sets status='paid', activates the tenant, and sets subscription_ends_at.
    """
    payment = db.query(BillingPayment).filter(BillingPayment.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Paiement introuvable")
    if payment.status != "pending":
        raise HTTPException(status_code=400, detail=f"Paiement déjà en statut '{payment.status}'")

    tenant = db.query(Tenant).filter(Tenant.id == payment.tenant_id).first()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant introuvable")

    now      = datetime.now(timezone.utc)
    stored_months = getattr(payment, "months", 1) or 1
    months   = max(1, body.months if body.months is not None else stored_months)
    period_end = now + timedelta(days=30 * months)

    payment.status     = "paid"
    payment.paid_at    = now
    payment.months     = months
    payment.period_end = encrypt_date(period_end, payment.tenant_id)
    db.flush()

    _activate_tenant(db, tenant, months=months)

    return {
        "status":               "ok",
        "payment_id":           payment.id,
        "invoice_number":       payment.invoice_number,
        "tenant":               tenant.slug,
        "new_tenant_status":    tenant.status,
        "subscription_ends_at": tenant.subscription_ends_at.isoformat(),
    }


# ── All payments ────────────────────────────────────────────────────────────

@router.get("/payments")
def list_payments(
    limit: int = 100,
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    payments = (
        db.query(BillingPayment)
        .order_by(BillingPayment.created_at.desc())
        .limit(limit)
        .all()
    )

    # Build a lookup of tenant_id → business_name to avoid N+1
    tenant_ids = list({p.tenant_id for p in payments})
    tenants = db.query(Tenant).filter(Tenant.id.in_(tenant_ids)).all()
    tenant_map = {t.id: t.business_name for t in tenants}

    return [
        _serialize_payment(p, tenant_map.get(p.tenant_id, "—"))
        for p in payments
    ]


# ── Platform config ─────────────────────────────────────────────────────────

@router.get("/platform-config")
def get_platform_config(
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    cfg = _get_platform_config(db)
    return {
        "id":                cfg.id,
        "moncash_number":    cfg.moncash_number,
        "natcash_number":    cfg.natcash_number,
        "monthly_price_htg": float(cfg.monthly_price_htg),
        "monthly_price_usd": float(cfg.monthly_price_usd),
        "stripe_price_id":   cfg.stripe_price_id,
        "trial_days":        cfg.trial_days,
        "support_email":     cfg.support_email,
        "support_whatsapp":  cfg.support_whatsapp,
        "moncash_mode":      cfg.moncash_mode or "manual",
        "natcash_mode":      cfg.natcash_mode or "manual",
        "price_per_extra_caisse_htg": float(cfg.price_per_extra_caisse_htg),
        "price_per_extra_caisse_usd": float(cfg.price_per_extra_caisse_usd),
        "price_per_extra_depot_htg":  float(getattr(cfg, "price_per_extra_depot_htg", 500.0)),
        "price_per_extra_depot_usd":  float(getattr(cfg, "price_per_extra_depot_usd", 4.0)),
        "created_at":        cfg.created_at.isoformat() if cfg.created_at else None,
        "updated_at":        cfg.updated_at.isoformat() if cfg.updated_at else None,
    }


@router.put("/platform-config")
def update_platform_config(
    body: PlatformConfigUpdate,
    db: Session = Depends(get_db),
    _: dict = Depends(require_superadmin),
):
    cfg = _get_platform_config(db)

    if body.moncash_number    is not None: cfg.moncash_number    = body.moncash_number
    if body.natcash_number    is not None: cfg.natcash_number    = body.natcash_number
    if body.monthly_price_htg is not None: cfg.monthly_price_htg = body.monthly_price_htg
    if body.monthly_price_usd is not None: cfg.monthly_price_usd = body.monthly_price_usd
    if body.stripe_price_id   is not None: cfg.stripe_price_id   = body.stripe_price_id
    if body.trial_days        is not None: cfg.trial_days        = body.trial_days
    if body.support_email     is not None: cfg.support_email     = body.support_email
    if body.support_whatsapp  is not None: cfg.support_whatsapp  = body.support_whatsapp
    if body.moncash_mode is not None:
        if body.moncash_mode not in ("manual", "api"):
            raise HTTPException(status_code=400, detail="moncash_mode invalide: 'manual' ou 'api'")
        cfg.moncash_mode = body.moncash_mode
    if body.natcash_mode is not None:
        if body.natcash_mode not in ("manual", "api"):
            raise HTTPException(status_code=400, detail="natcash_mode invalide: 'manual' ou 'api'")
        cfg.natcash_mode = body.natcash_mode

    if body.price_per_extra_caisse_htg is not None:
        cfg.price_per_extra_caisse_htg = body.price_per_extra_caisse_htg
    if body.price_per_extra_caisse_usd is not None:
        cfg.price_per_extra_caisse_usd = body.price_per_extra_caisse_usd
    if body.price_per_extra_depot_htg is not None:
        cfg.price_per_extra_depot_htg = body.price_per_extra_depot_htg
    if body.price_per_extra_depot_usd is not None:
        cfg.price_per_extra_depot_usd = body.price_per_extra_depot_usd

    db.commit()
    db.refresh(cfg)

    return {
        "id":                cfg.id,
        "moncash_number":    cfg.moncash_number,
        "natcash_number":    cfg.natcash_number,
        "monthly_price_htg": float(cfg.monthly_price_htg),
        "monthly_price_usd": float(cfg.monthly_price_usd),
        "stripe_price_id":   cfg.stripe_price_id,
        "trial_days":        cfg.trial_days,
        "support_email":     cfg.support_email,
        "support_whatsapp":  cfg.support_whatsapp,
        "moncash_mode":      cfg.moncash_mode or "manual",
        "natcash_mode":      cfg.natcash_mode or "manual",
        "price_per_extra_caisse_htg": float(cfg.price_per_extra_caisse_htg),
        "price_per_extra_caisse_usd": float(cfg.price_per_extra_caisse_usd),
        "price_per_extra_depot_htg":  float(getattr(cfg, "price_per_extra_depot_htg", 500.0)),
        "price_per_extra_depot_usd":  float(getattr(cfg, "price_per_extra_depot_usd", 4.0)),
        "updated_at":        cfg.updated_at.isoformat() if cfg.updated_at else None,
    }
