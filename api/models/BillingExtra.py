from sqlalchemy import Column, String, DateTime, ForeignKey
from .base import UUIDBase


class BillingExtra(UUIDBase):
    """Tracks each extra caisse/dépôt beyond plan limit for prorated billing."""
    __tablename__ = "billing_extras"

    tenant_id     = Column(String(36), ForeignKey('tenants.id'), nullable=False, index=True)
    resource_type = Column(String(20), nullable=False)   # 'caisse' | 'depot'
    resource_id   = Column(String(36), nullable=True)    # PosRegister.id or Warehouse.id
    started_at    = Column(DateTime(timezone=True), nullable=False)
    ended_at      = Column(DateTime(timezone=True), nullable=True)  # null = still active
