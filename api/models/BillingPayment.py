from sqlalchemy import Column, Integer, String, Numeric, DateTime, ForeignKey, Text
from .base import UUIDBase


class BillingPayment(UUIDBase):
    """One row per SaaS subscription payment received for a tenant."""
    __tablename__ = "billing_payments"

    tenant_id      = Column(String(36), ForeignKey('tenants.id'), nullable=False, index=True)
    invoice_number = Column(String(30), nullable=False, unique=True)  # INV-2026-0001
    method         = Column(String(20), nullable=False)               # stripe | moncash | natcash | manual
    amount         = Column(Numeric(10, 2), nullable=False)
    currency       = Column(String(10), nullable=False, default='USD')
    status         = Column(String(20), nullable=False, default='paid')  # paid | refunded
    months         = Column(Integer, nullable=False, default=1)
    reference      = Column(String(200), nullable=True)   # Stripe payment_intent / MonCash txn
    description    = Column(String(300), nullable=True)
    paid_at        = Column(DateTime(timezone=True), nullable=True)
    # Fernet-encrypted ISO datetimes — key = HKDF(SECRET_KEY, salt=tenant_id)
    period_start   = Column(Text, nullable=True)
    period_end     = Column(Text, nullable=True)
