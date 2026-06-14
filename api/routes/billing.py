from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime, timezone, timedelta
from math import ceil
from typing import List

from api.database import get_db
from api.models.User import User
from api.models.Tenant import Tenant
from api.models.BillingPayment import BillingPayment
from api.models.PlatformConfig import PlatformConfig
from api.core.config import settings
from api.core.billing_crypto import try_decrypt_date
from api.dependencies.auth import require_permission
from api.core.permissions import P

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
        "has_stripe": bool(tenant.stripe_subscription_id),
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
