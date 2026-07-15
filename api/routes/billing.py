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
from api.core.config import settings
from api.core.billing_crypto import try_decrypt_date, encrypt_date
from api.dependencies.auth import require_permission
from api.core.permissions import P


class SubmitPaymentRequest(BaseModel):
    method: str          # moncash | natcash
    amount: float
    currency: str = "HTG"
    reference: str       # numéro de transaction / reçu
    description: str | None = None

router = APIRouter(prefix="/api/billing", tags=["Billing"])


def _get_tenant(db: Session, user: User) -> Tenant:
    if not user.tenant_id:
        raise HTTPException(status_code=400, detail="Compte local — pas d'abonnement cloud")
    tenant = db.query(Tenant).filter(Tenant.id == user.tenant_id).first()
    if not tenant or tenant.is_local:
        raise HTTPException(status_code=400, detail="Pas de tenant cloud associé")
    return tenant


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
    }


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

    users = db.query(User).filter(User.tenant_id == tenant.id).all()
    caisse_count = sum(
        1 for u in users
        if u.roles and "cashier" in (u.roles if isinstance(u.roles, list) else [])
    )

    cfg = db.query(PlatformConfig).first()
    price_extra_htg = float(cfg.price_per_extra_caisse_htg) if cfg else 500.0
    price_extra_usd = float(cfg.price_per_extra_caisse_usd) if cfg else 4.0

    return {
        "tenant_id":            tenant.id,
        "tenant_type":          tenant.type,
        "self_hosted_url":      tenant.self_hosted_url or None,
        "can_manage_tenants":   tenant.can_manage_tenants,
        "status":               tenant.status,
        "issued_at":            now.isoformat(),
        "valid_until":          valid_until.isoformat(),
        "trial_ends_at":        trial_end.isoformat() if trial_end else None,
        "subscription_ends_at": sub_end.isoformat() if sub_end else None,
        "max_caisses":          tenant.max_caisses,
        "current_caisses":      caisse_count,
        "price_per_extra_caisse_htg": price_extra_htg,
        "price_per_extra_caisse_usd": price_extra_usd,
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
    return _sign_payload(_build_license_payload(tenant, db))


@router.get("/caisse-count")
def get_caisse_count(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Returns current caisse count vs plan limit for the tenant."""
    tenant = _get_tenant(db, current_user)
    users  = db.query(User).filter(User.tenant_id == tenant.id).all()
    count  = sum(
        1 for u in users
        if u.roles and "cashier" in (u.roles if isinstance(u.roles, list) else [])
    )
    cfg = db.query(PlatformConfig).first()
    return {
        "current_caisses": count,
        "max_caisses":     tenant.max_caisses,
        "over_limit":      count > tenant.max_caisses,
        "extra_count":     max(0, count - tenant.max_caisses),
        "price_per_extra_htg": float(cfg.price_per_extra_caisse_htg) if cfg else 500.0,
        "price_per_extra_usd": float(cfg.price_per_extra_caisse_usd) if cfg else 4.0,
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
    if body.method not in ("moncash", "natcash"):
        raise HTTPException(status_code=400, detail="Méthode invalide : moncash ou natcash")

    tenant = _get_tenant(db, current_user)

    # Prevent duplicate submission of the same reference
    existing = db.query(BillingPayment).filter(
        BillingPayment.tenant_id == tenant.id,
        BillingPayment.reference == body.reference,
    ).first()
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"Une soumission avec la référence '{body.reference}' existe déjà (statut: {existing.status})",
        )

    now = datetime.now(timezone.utc)
    # Generate invoice number (prefix differs to distinguish pending from paid)
    year   = now.year
    prefix = f"PEND-{year}-"
    count  = db.query(BillingPayment).filter(
        BillingPayment.tenant_id == tenant.id,
        BillingPayment.invoice_number.like(f"{prefix}%"),
    ).count()
    invoice_number = f"{prefix}{count + 1:04d}"

    payment = BillingPayment(
        tenant_id=tenant.id,
        invoice_number=invoice_number,
        method=body.method,
        amount=body.amount,
        currency=body.currency,
        status="pending",
        reference=body.reference,
        description=body.description or f"Paiement {body.method.capitalize()} — en attente de confirmation",
        paid_at=None,
        period_start=encrypt_date(now, tenant.id),
        period_end=encrypt_date(now + timedelta(days=30), tenant.id),
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
