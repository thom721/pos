from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from .base import UUIDBase


class PosRegister(UUIDBase):
    __tablename__ = "pos_registers"

    tenant_id     = Column(String(36), ForeignKey('tenants.id'), nullable=False, index=True)
    warehouse_id  = Column(String(36), ForeignKey('warehouses.id'), nullable=True, index=True)
    name          = Column(String(100), nullable=False)
    device_id     = Column(String(36),  nullable=True)   # NULL until a device claims this slot
    is_active     = Column(Boolean, nullable=False, default=True)
    # Session tracking
    session_token = Column(String(36), nullable=True)   # UUID rotated at each login; JWT sid must match
    last_seen     = Column(DateTime(timezone=True), nullable=True)  # updated by heartbeat every 2 min

    # ── Abonnement par caisse (caisses supplémentaires) ──────────────────────────
    # trial_ends_at     : fin de la période d'essai de cette caisse (NULL = caisse de base)
    # subscription_ends_at : fin de l'abonnement payé pour cette caisse
    # NULL = caisse de base incluse dans le plan tenant, pas de facturation individuelle
    trial_ends_at        = Column(DateTime(timezone=True), nullable=True)
    subscription_ends_at = Column(DateTime(timezone=True), nullable=True)

    warehouse = relationship("Warehouse", back_populates="pos_registers")

    __table_args__ = (
        UniqueConstraint('tenant_id', 'device_id', name='uq_register_tenant_device'),
    )
