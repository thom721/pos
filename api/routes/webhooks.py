"""
Payment webhooks — Stripe, MonCash, NatCash.
These endpoints are called by the payment providers to confirm a payment
and activate (or renew) a tenant's subscription.
"""
import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Request, HTTPException, Header
from sqlalchemy.orm import Session
from pydantic import BaseModel

from api.database import get_db
from api.models.Tenant import Tenant
from api.models.BillingPayment import BillingPayment
from api.core.config import settings
from api.core.billing_crypto import encrypt_date

router = APIRouter(prefix="/api/webhooks", tags=["Webhooks"])
_log = logging.getLogger("pos.webhooks")


# ── Helpers ────────────────────────────────────────────────────────────────

def _next_invoice_number(db: Session, tenant_id: str) -> str:
    year = datetime.now(timezone.utc).year
    prefix = f"INV-{year}-"
    count = db.query(BillingPayment).filter(
        BillingPayment.tenant_id == tenant_id,
        BillingPayment.invoice_number.like(f"{prefix}%"),
    ).count()
    return f"{prefix}{count + 1:04d}"


def _record_payment(
    db: Session,
    tenant_id: str,
    method: str,
    amount: float,
    currency: str = "USD",
    reference: str | None = None,
    description: str | None = None,
    period_start: datetime | None = None,
    period_end: datetime | None = None,
) -> BillingPayment:
    payment = BillingPayment(
        tenant_id=tenant_id,
        invoice_number=_next_invoice_number(db, tenant_id),
        method=method,
        amount=amount,
        currency=currency,
        status="paid",
        reference=reference,
        description=description or "Abonnement POS Connect",
        paid_at=datetime.now(timezone.utc),
        period_start=encrypt_date(period_start, tenant_id) if period_start else None,
        period_end=encrypt_date(period_end, tenant_id) if period_end else None,
    )
    db.add(payment)
    db.flush()
    return payment


def _activate_tenant(db: Session, tenant: Tenant) -> None:
    """Mark tenant as active and set/renew subscription for 30 days."""
    tenant.status = "active"
    tenant.subscription_started_at = datetime.now(timezone.utc)
    db.commit()
    _log.info("Tenant activé : %s (%s)", tenant.slug, tenant.id)


def _get_tenant_by_id(db: Session, tenant_id: str) -> Tenant:
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant introuvable")
    return tenant


# ── Stripe ─────────────────────────────────────────────────────────────────

@router.post("/stripe")
async def stripe_webhook(
    request: Request,
    stripe_signature: str = Header(None, alias="stripe-signature"),
    db: Session = Depends(get_db),
):
    import json

    body = await request.body()

    stripe_webhook_secret = getattr(settings, "STRIPE_WEBHOOK_SECRET", "")
    if stripe_webhook_secret and stripe_signature:
        try:
            import stripe as stripe_lib
            event = stripe_lib.Webhook.construct_event(
                body, stripe_signature, stripe_webhook_secret
            )
        except Exception as e:
            _log.warning("Stripe signature invalide: %s", e)
            raise HTTPException(status_code=400, detail="Invalid signature")
    else:
        event = json.loads(body)

    event_type = event.get("type", "")
    data = event.get("data", {}).get("object", {})

    _log.info("Stripe event: %s", event_type)

    if event_type in ("checkout.session.completed", "invoice.payment_succeeded"):
        tenant_id = (
            data.get("metadata", {}).get("tenant_id")
            or data.get("client_reference_id")
        )
        if tenant_id:
            tenant = _get_tenant_by_id(db, tenant_id)
            if data.get("subscription"):
                tenant.stripe_subscription_id = data["subscription"]
            if data.get("customer"):
                tenant.stripe_customer_id = data["customer"]

            # Record payment
            amount_cents = data.get("amount_paid") or data.get("amount_total") or 0
            currency = (data.get("currency") or "usd").upper()
            period = data.get("lines", {}).get("data", [{}])[0].get("period", {})
            period_start = datetime.fromtimestamp(period["start"], tz=timezone.utc) if period.get("start") else None
            period_end   = datetime.fromtimestamp(period["end"],   tz=timezone.utc) if period.get("end")   else None

            _record_payment(
                db, tenant_id,
                method="stripe",
                amount=amount_cents / 100,
                currency=currency,
                reference=data.get("payment_intent") or data.get("id"),
                description=f"Abonnement POS Connect — Stripe",
                period_start=period_start,
                period_end=period_end,
            )
            _activate_tenant(db, tenant)

    elif event_type == "customer.subscription.deleted":
        stripe_sub_id = data.get("id")
        if stripe_sub_id:
            tenant = db.query(Tenant).filter(
                Tenant.stripe_subscription_id == stripe_sub_id
            ).first()
            if tenant:
                tenant.status = "suspended"
                db.commit()
                _log.info("Tenant suspendu (Stripe annulé): %s", tenant.slug)

    return {"status": "ok"}


# ── MonCash ────────────────────────────────────────────────────────────────

class MonCashPaymentNotif(BaseModel):
    tenant_id: str
    transaction_id: str
    amount: float
    currency: str = "HTG"
    status: str


@router.post("/moncash")
def moncash_webhook(payload: MonCashPaymentNotif, db: Session = Depends(get_db)):
    _log.info("MonCash notif: tenant=%s txn=%s status=%s",
              payload.tenant_id, payload.transaction_id, payload.status)

    if payload.status != "SUCCESS":
        return {"status": "ignored", "reason": "payment not successful"}

    tenant = _get_tenant_by_id(db, payload.tenant_id)
    _record_payment(
        db, payload.tenant_id,
        method="moncash",
        amount=payload.amount,
        currency=payload.currency,
        reference=payload.transaction_id,
        description="Abonnement POS Connect — MonCash",
    )
    _activate_tenant(db, tenant)
    return {"status": "ok", "tenant": tenant.slug}


# ── NatCash ────────────────────────────────────────────────────────────────

class NatCashPaymentNotif(BaseModel):
    tenant_id: str
    reference: str
    amount: float
    currency: str = "HTG"
    status: str


@router.post("/natcash")
def natcash_webhook(payload: NatCashPaymentNotif, db: Session = Depends(get_db)):
    _log.info("NatCash notif: tenant=%s ref=%s status=%s",
              payload.tenant_id, payload.reference, payload.status)

    if payload.status != "COMPLETED":
        return {"status": "ignored", "reason": "payment not completed"}

    tenant = _get_tenant_by_id(db, payload.tenant_id)
    _record_payment(
        db, payload.tenant_id,
        method="natcash",
        amount=payload.amount,
        currency=payload.currency,
        reference=payload.reference,
        description="Abonnement POS Connect — NatCash",
    )
    _activate_tenant(db, tenant)
    return {"status": "ok", "tenant": tenant.slug}


# ── Manual activation (admin use) ─────────────────────────────────────────

class ManualActivation(BaseModel):
    tenant_id: str
    admin_secret: str
    amount: float = 0.0
    currency: str = "HTG"
    reference: str | None = None


@router.post("/activate")
def manual_activate(payload: ManualActivation, db: Session = Depends(get_db)):
    admin_secret = getattr(settings, "ADMIN_SECRET", "")
    if not admin_secret or payload.admin_secret != admin_secret:
        raise HTTPException(status_code=403, detail="Secret admin invalide")

    tenant = _get_tenant_by_id(db, payload.tenant_id)
    if payload.amount > 0:
        _record_payment(
            db, payload.tenant_id,
            method="manual",
            amount=payload.amount,
            currency=payload.currency,
            reference=payload.reference,
            description="Abonnement POS Connect — Activation manuelle",
        )
    _activate_tenant(db, tenant)
    return {"status": "ok", "tenant": tenant.slug, "new_status": tenant.status}
