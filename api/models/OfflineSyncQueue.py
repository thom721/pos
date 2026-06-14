from sqlalchemy import Column, String, JSON, Text, DateTime, ForeignKey
from .base import UUIDBase


class OfflineSyncQueue(UUIDBase):
    """
    Stores sales (and future operations) that were made offline and are
    waiting to be replayed against the cloud DB.
    """
    __tablename__ = "offline_sync_queue"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),       nullable=False, index=True)
    register_id  = Column(String(36), ForeignKey('pos_registers.id'), nullable=True)
    device_id    = Column(String(36), nullable=False)

    # 'sale' — extendable to 'purchase', 'return', etc.
    operation_type = Column(String(50), nullable=False, default='sale')

    # Full JSON payload of the operation (e.g. SaleCreate dict)
    payload = Column(JSON, nullable=False)

    # Temporary client-side ID so the app can map responses back
    local_temp_id = Column(String(100), nullable=True)

    # Timestamp from the device clock (may differ from server created_at)
    created_at_device = Column(DateTime(timezone=True), nullable=False)

    # Set by server after successful replay
    processed_at       = Column(DateTime(timezone=True), nullable=True)
    assigned_reference = Column(String(100), nullable=True)  # e.g. VNT-00045

    # 'pending' | 'processed' | 'conflict'
    status        = Column(String(20), nullable=False, default='pending', index=True)
    conflict_note = Column(Text, nullable=True)
