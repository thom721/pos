import uuid
from sqlalchemy import Column, String, Boolean, DateTime, Integer, Text
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
    stripe_customer_id     = Column(String(100), nullable=True)
    stripe_subscription_id = Column(String(100), nullable=True)
    subscription_ends_at   = Column(DateTime(timezone=True), nullable=True)

    # 'shared' = data hébergée sur posconnect.ht
    # 'selfhosted' = data sur le propre serveur du tenant, seul billing sync posconnect.ht
    type             = Column(String(20),  nullable=False, default='shared')
    self_hosted_url  = Column(String(500), nullable=True)

    # Nombre de caisses inclus dans le plan (positionnable par le superadmin)
    max_caisses = Column(Integer, nullable=False, default=1)

    # Autorise ce tenant self-hosted à gérer ses propres sous-tenants
    can_manage_tenants = Column(Boolean, nullable=False, default=False)

    # Suivi des notifications d'expiration envoyées
    last_warning_sent_at = Column(DateTime(timezone=True), nullable=True)
