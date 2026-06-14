import uuid
from sqlalchemy import Column, String, Boolean, DateTime, Text
from .base import UUIDBase


class Tenant(UUIDBase):
    __tablename__ = "tenants"

    slug          = Column(String(100), unique=True, nullable=False, index=True)
    business_name = Column(String(200), nullable=False)
    owner_email   = Column(String(255), unique=True, nullable=False, index=True)
    phone         = Column(String(50),  nullable=True)

    # 'trial' | 'active' | 'suspended' | 'local'
    status              = Column(String(20), nullable=False, default='trial')
    trial_ends_at       = Column(DateTime(timezone=True), nullable=True)
    subscription_started_at = Column(DateTime(timezone=True), nullable=True)

    # True only for the auto-created LOCAL tenant on local-mode deployments
    is_local = Column(Boolean, nullable=False, default=False)

    # Stripe / payment
    stripe_customer_id  = Column(String(100), nullable=True)
    stripe_subscription_id = Column(String(100), nullable=True)
