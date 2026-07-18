from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from datetime import datetime, timezone, timedelta
from math import ceil
from typing import List

from pydantic import BaseModel

from api.database import get_db
from api.models.User import User
from api.models.Tenant import Tenant
from api.models.BillingPayment import BillingPayment
from api.models.PlatformConfig import PlatformConfig
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.core.config import settings
from api.core.billing_crypto import try_decrypt_date, encrypt_date
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.services import billing_extra_service as _billing


class SubmitPaymentRequest(BaseModel):
    method: str = "manual"        # moncash | natcash | manual
    months: int = 1               # 1–12
    reference: str | None = None  # preuve de transaction optionnelle

router = APIRouter(prefix="/api/billing", tags=["Billing"])


def _get_tenant(db: Session, user: User) -> Tenant:
    if not user.tenant_id:
        raise HTTPException(status_code=400, detail="Compte local — pas d'abonnement cloud")
    tenant = db.query(Tenant).filter(Tenant.id == user.tenant_id).first()
    if not tenant or tenant.is_local:
        raise HTTPException(status_code=400, detail="Pas de tenant cloud associé")
    return tenant


def _compute_plan_usage(tenant: Tenant, db: Session, cfg: PlatformConfig | None) -> dict:
    """Calcule le détail d'utilisation du plan et le total du cycle en cours (avec prorata)."""
    # Caisses = PosRegisters actifs (cohérent avec l'enforcement de limite)
    caisse_count = db.query(PosRegister).filter(
        PosRegister.tenant_id == tenant.id,
        PosRegister.is_active == True,  # noqa: E712
    ).count()
    # Dépôts = warehouses actifs
    depot_count = db.query(Warehouse).filter(
        Warehouse.tenant_id == tenant.id,
        Warehouse.is_active == True,  # noqa: E712
    ).count()

    max_caisses = tenant.max_caisses
    max_depots  = getattr(tenant, "max_depots", 1)

    base_htg = float(cfg.monthly_price_htg)             if cfg else 1500.0
    base_usd = float(cfg.monthly_price_usd)             if cfg else 12.0
    xc_htg   = float(cfg.price_per_extra_caisse_htg)    if cfg else 500.0
    xc_usd   = float(cfg.price_per_extra_caisse_usd)    if cfg else 4.0
    xd_htg   = float(getattr(cfg, "price_per_extra_depot_htg", 500.0)) if cfg else 500.0
    xd_usd   = float(getattr(cfg, "price_per_extra_depot_usd", 4.0))   if cfg else 4.0

    extra_caisses = max(0, caisse_count - max_caisses)
    extra_depots  = max(0, depot_count  - max_depots)

    # Cycle de facturation courant : commence à subscription_started_at (jour du mois)
    now = datetime.now(timezone.utc)
    sub_start = getattr(tenant, "subscription_started_at", None)
    if sub_start:
        if sub_start.tzinfo is None:
            sub_start = sub_start.replace(tzinfo=timezone.utc)
        # Trouver le début du cycle courant (même jour du mois que sub_start)
        cycle_start = sub_start.replace(year=now.year, month=now.month)
        if cycle_start > now:
            # On est avant le jour de renouvellement ce mois — le cycle a commencé le mois passé
            m = now.month - 1 or 12
            y = now.year if now.month > 1 else now.year - 1
            cycle_start = sub_start.replace(year=y, month=m)
        cycle_end = cycle_start + timedelta(days=30)
    else:
        # Pas encore abonné : cycle = mois calendaire courant
        cycle_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        cycle_end   = (cycle_start + timedelta(days=32)).replace(day=1)

    # Prorata sur les extras
    prorated = _billing.compute_prorated(
        db, tenant.id, cycle_start, cycle_end,
        xc_htg, xc_usd, xd_htg, xd_usd,
    )

    total_htg = base_htg + prorated["total_htg"]
    total_usd = base_usd + prorated["total_usd"]

    return {
        "max_caisses":                max_caisses,
        "current_caisses":            caisse_count,
        "extra_caisses":              extra_caisses,
        "price_per_extra_caisse_htg": xc_htg,
        "price_per_extra_caisse_usd": xc_usd,
        "max_depots":                 max_depots,
        "current_depots":             depot_count,
        "extra_depots":               extra_depots,
        "price_per_extra_depot_htg":  xd_htg,
        "price_per_extra_depot_usd":  xd_usd,
        "base_price_htg":             base_htg,
        "base_price_usd":             base_usd,
        "prorated_extras_htg":        prorated["total_htg"],
        "prorated_extras_usd":        prorated["total_usd"],
        "prorated_breakdown":         prorated["extras"],
        "cycle_start":                cycle_start.isoformat(),
        "cycle_end":                  cycle_end.isoformat(),
        "total_monthly_htg":          total_htg,
        "total_monthly_usd":          total_usd,
    }


@router.get("/config")
def get_billing_config(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Returns platform payment config visible to tenants (numbers, prices, modes)."""
    cfg = db.query(PlatformConfig).first()
    if not cfg:
        return {
            "moncash_number": "", "natcash_number": "",
            "monthly_price_htg": 1500.0, "monthly_price_usd": 12.0,
            "moncash_mode": "manual", "natcash_mode": "manual",
            "support_email": "", "support_whatsapp": "",
            "price_per_extra_caisse_htg": 500.0, "price_per_extra_caisse_usd": 4.0,
            "price_per_extra_depot_htg":  500.0, "price_per_extra_depot_usd":  4.0,
        }
    return {
        "moncash_number":    cfg.moncash_number,
        "natcash_number":    cfg.natcash_number,
        "monthly_price_htg": float(cfg.monthly_price_htg),
        "monthly_price_usd": float(cfg.monthly_price_usd),
        "moncash_mode":      cfg.moncash_mode or "manual",
        "natcash_mode":      cfg.natcash_mode or "manual",
        "support_email":     cfg.support_email,
        "support_whatsapp":  cfg.support_whatsapp,
        "price_per_extra_caisse_htg": float(cfg.price_per_extra_caisse_htg),
        "price_per_extra_caisse_usd": float(cfg.price_per_extra_caisse_usd),
        "price_per_extra_depot_htg":  float(getattr(cfg, "price_per_extra_depot_htg", 500.0)),
        "price_per_extra_depot_usd":  float(getattr(cfg, "price_per_extra_depot_usd", 4.0)),
    }


@router.get("/status")
def get_billing_status(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Returns the current subscription status for the tenant."""
    tenant = _get_tenant(db, current_user)

    trial_end = tenant.trial_ends_at
    if trial_end and trial_end.tzinfo is None:
        trial_end = trial_end.replace(tzinfo=timezone.utc)

    from api.core.tenant import GRACE_DAYS
    now = datetime.now(timezone.utc)
    days_left = None
    is_grace = False
    grace_days_left = None

    if trial_end and tenant.status in ("trial", "expired"):
        delta = trial_end - now
        if delta.total_seconds() > 0:
            days_left = max(0, ceil(delta.total_seconds() / 86400))
        else:
            # In grace period
            is_grace = True
            grace_end = trial_end + timedelta(days=GRACE_DAYS)
            grace_delta = grace_end - now
            grace_days_left = max(0, ceil(grace_delta.total_seconds() / 86400))

    sub_end = getattr(tenant, "subscription_ends_at", None)
    if sub_end and sub_end.tzinfo is None:
        sub_end = sub_end.replace(tzinfo=timezone.utc)

    return {
        "status": tenant.status,
        "business_name": tenant.business_name,
        "owner_email": tenant.owner_email,
        "trial_ends_at": trial_end.isoformat() if trial_end else None,
        "days_left": days_left,
        "is_grace": is_grace,
        "grace_days_left": grace_days_left,
        "subscription_started_at": tenant.subscription_started_at.isoformat()
            if tenant.subscription_started_at else None,
        "subscription_ends_at": sub_end.isoformat() if sub_end else None,
        "has_stripe": bool(tenant.stripe_subscription_id),
        "max_caisses": tenant.max_caisses,
        "max_depots": getattr(tenant, "max_depots", 1),
    }


@router.get("/plan-usage")
def get_plan_usage(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Retourne le détail d'utilisation du plan : caisses + dépôts + total mensuel calculé."""
    tenant = _get_tenant(db, current_user)
    cfg    = db.query(PlatformConfig).first()
    return _compute_plan_usage(tenant, db, cfg)


def _build_license_payload(tenant: "Tenant", db: Session) -> dict:
    """Build the raw license payload dict (shared by both license endpoints)."""
    now         = datetime.now(timezone.utc)
    valid_until = now + timedelta(days=7)

    trial_end = tenant.trial_ends_at
    if trial_end and trial_end.tzinfo is None:
        trial_end = trial_end.replace(tzinfo=timezone.utc)

    sub_end = getattr(tenant, "subscription_ends_at", None)
    if sub_end and sub_end.tzinfo is None:
        sub_end = sub_end.replace(tzinfo=timezone.utc)

    cfg   = db.query(PlatformConfig).first()
    usage = _compute_plan_usage(tenant, db, cfg)

    return {
        "tenant_id":            tenant.id,
        "tenant_type":          getattr(tenant, "type", "shared"),
        "self_hosted_url":      getattr(tenant, "self_hosted_url", None) or None,
        "can_manage_tenants":   getattr(tenant, "can_manage_tenants", False),
        "status":               tenant.status,
        "issued_at":            now.isoformat(),
        "valid_until":          valid_until.isoformat(),
        "trial_ends_at":        trial_end.isoformat() if trial_end else None,
        "subscription_ends_at": sub_end.isoformat() if sub_end else None,
        **usage,
    }


def _sign_payload(payload: dict) -> dict:
    """Sign a payload dict with IDENTITY_PRIVATE_KEY. Returns {data, signature}."""
    import json
    import base64
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    raw_key = settings.IDENTITY_PRIVATE_KEY
    if not raw_key:
        raise HTTPException(503, "Identité serveur non configurée (IDENTITY_PRIVATE_KEY)")
    try:
        key_bytes  = base64.b64decode(raw_key)
        priv       = Ed25519PrivateKey.from_private_bytes(key_bytes)
        data_bytes = json.dumps(payload, separators=(",", ":")).encode()
        signature  = priv.sign(data_bytes)
        return {
            "data":      base64.b64encode(data_bytes).decode(),
            "signature": base64.b64encode(signature).decode(),
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, f"Erreur signature licence: {exc}")


@router.get("/license-sync-proxy")
def get_license_sync_proxy(
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Called by self-hosted / local servers proxying for their Flutter clients.
    Accepts a sync token (Bearer) instead of a user JWT.
    Returns a signed license blob (signed with IDENTITY_PRIVATE_KEY on posconnect.ht).
    """
    from api.routes.sync import _decode_sync_token

    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(401, "Token de synchronisation requis")

    claims = _decode_sync_token(auth_header[7:])
    tenant = db.query(Tenant).filter(Tenant.id == claims["tenant_id"]).first()
    if not tenant:
        raise HTTPException(404, "Tenant introuvable")

    return _sign_payload(_build_license_payload(tenant, db))


@router.get("/license")
def get_license(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """
    Returns a signed license blob the Flutter app caches locally.
    - If BILLING_URL is configured (self-hosted / local server): proxies to
      posconnect.ht using the stored sync token — transparent to Flutter clients.
    - Otherwise (running ON posconnect.ht): signs and returns directly.
    Signed with IDENTITY_PRIVATE_KEY (Ed25519) — verifiable without internet.
    """
    # ── Proxy mode: self-hosted / local server ────────────────────────────────
    # BILLING_URL is set when this server is NOT posconnect.ht (set by wizard).
    # In that case, proxy to posconnect.ht using the stored sync token so that
    # the signed blob comes from posconnect.ht (Flutter verifies with hardcoded key).
    import httpx as _httpx

    billing_url  = (settings.BILLING_URL or "").rstrip("/")
    sync_token   = settings.CLOUD_SYNC_TOKEN or ""

    if billing_url and sync_token:
        try:
            r = _httpx.get(
                f"{billing_url}/api/billing/license-sync-proxy",
                headers={"Authorization": f"Bearer {sync_token}"},
                timeout=10,
            )
            r.raise_for_status()
            return r.json()
        except _httpx.HTTPStatusError as exc:
            raise HTTPException(exc.response.status_code,
                                f"Erreur billing proxy: {exc.response.text[:200]}")
        except Exception as exc:
            raise HTTPException(503, f"Serveur de billing inaccessible: {exc}")

    # ── Direct mode: this IS posconnect.ht ───────────────────────────────────
    tenant = _get_tenant(db, current_user)
    try:
        payload = _build_license_payload(tenant, db)
    except Exception as exc:
        raise HTTPException(500, f"Erreur construction licence: {exc}")
    return _sign_payload(payload)


@router.get("/caisse-count")
def get_caisse_count(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Retourne le décompte caisses + dépôts vs limites du plan (alias de plan-usage)."""
    tenant = _get_tenant(db, current_user)
    cfg    = db.query(PlatformConfig).first()
    usage  = _compute_plan_usage(tenant, db, cfg)
    # Compatibilité avec les anciens champs
    return {
        **usage,
        "current_caisses": usage["current_caisses"],
        "max_caisses":     usage["max_caisses"],
        "over_limit":      usage["extra_caisses"] > 0 or usage["extra_depots"] > 0,
        "extra_count":     usage["extra_caisses"],
        "price_per_extra_htg": usage["price_per_extra_caisse_htg"],
        "price_per_extra_usd": usage["price_per_extra_caisse_usd"],
    }


@router.get("/payments")
def list_payments(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Returns all billing payments for the current tenant, newest first."""
    tenant = _get_tenant(db, current_user)
    payments = (
        db.query(BillingPayment)
        .filter(BillingPayment.tenant_id == tenant.id)
        .order_by(BillingPayment.created_at.desc())
        .all()
    )
    result = []
    for p in payments:
        period_start = try_decrypt_date(p.period_start, p.tenant_id)
        period_end   = try_decrypt_date(p.period_end,   p.tenant_id)
        result.append({
            "id": p.id,
            "invoice_number": p.invoice_number,
            "method": p.method,
            "amount": float(p.amount),
            "currency": p.currency,
            "status": p.status,
            "reference": p.reference,
            "description": p.description,
            "paid_at": p.paid_at.isoformat() if p.paid_at else None,
            "period_start": period_start.isoformat() if period_start else None,
            "period_end":   period_end.isoformat()   if period_end   else None,
            "created_at": p.created_at.isoformat(),
        })
    return result


@router.post("/checkout/stripe")
def create_stripe_checkout(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_UPDATE)),
):
    """Creates a Stripe Checkout session and returns the URL."""
    stripe_secret = getattr(settings, "STRIPE_SECRET_KEY", "")
    stripe_price  = getattr(settings, "STRIPE_PRICE_ID", "")
    success_url   = getattr(settings, "STRIPE_SUCCESS_URL", "")
    cancel_url    = getattr(settings, "STRIPE_CANCEL_URL", "")

    if not stripe_secret or not stripe_price:
        raise HTTPException(
            status_code=503,
            detail="Paiement Stripe non configuré. Contactez l'administrateur.",
        )

    tenant = _get_tenant(db, current_user)

    try:
        import stripe as stripe_lib
        stripe_lib.api_key = stripe_secret

        session = stripe_lib.checkout.Session.create(
            mode="subscription",
            line_items=[{"price": stripe_price, "quantity": 1}],
            customer_email=tenant.owner_email,
            client_reference_id=tenant.id,
            success_url=success_url or "https://posconnect.ht/billing?success=1",
            cancel_url=cancel_url or "https://posconnect.ht/billing?cancelled=1",
        )
        return {"checkout_url": session.url}
    except ImportError:
        raise HTTPException(status_code=503, detail="Module stripe non installé côté serveur")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur Stripe: {str(e)}")


@router.post("/submit-payment", status_code=201)
def submit_payment(
    body: SubmitPaymentRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """
    Tenant submits proof of a MonCash/NatCash payment.
    Creates a BillingPayment with status='pending'.
    A superadmin must confirm it via PATCH /api/admin/payments/{id}/confirm.
    """
    if not 1 <= body.months <= 12:
        raise HTTPException(status_code=400, detail="Nombre de mois invalide (1–12)")

    tenant = _get_tenant(db, current_user)

    # Total mensuel = base + extras caisses + extras dépôts
    cfg    = db.query(PlatformConfig).first()
    usage  = _compute_plan_usage(tenant, db, cfg)
    amount = usage["total_monthly_htg"] * body.months

    now = datetime.now(timezone.utc)
    year   = now.year
    prefix = f"PEND-{year}-"
    count  = db.query(BillingPayment).filter(
        BillingPayment.tenant_id == tenant.id,
        BillingPayment.invoice_number.like(f"{prefix}%"),
    ).count()
    invoice_number = f"{prefix}{count + 1:04d}"

    months_label = f"{body.months} mois" if body.months > 1 else "1 mois"
    method_label = {"moncash": "MonCash", "natcash": "NatCash"}.get(body.method, "Manuel")
    payment = BillingPayment(
        tenant_id=tenant.id,
        invoice_number=invoice_number,
        method=body.method,
        amount=amount,
        currency="HTG",
        months=body.months,
        status="pending",
        reference=body.reference,
        description=f"Demande {method_label} — {months_label} ({amount:.0f} HTG) — en attente de paiement",
        paid_at=None,
        period_start=encrypt_date(now, tenant.id),
        period_end=encrypt_date(now + timedelta(days=30 * body.months), tenant.id),
    )
    db.add(payment)
    db.commit()
    db.refresh(payment)

    return {
        "status":         "pending",
        "invoice_number": payment.invoice_number,
        "payment_id":     payment.id,
        "message":        "Votre paiement a été soumis. Un administrateur le validera sous peu.",
    }
