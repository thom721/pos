from sqlalchemy import Column, String, Integer, DateTime, Text
from .base import UUIDBase


class SyncState(UUIDBase):
    """Tracks last push/pull timestamp per entity type on the local server."""
    __tablename__ = "sync_state"

    entity_type    = Column(String(50),  nullable=False, unique=True)
    last_push_at   = Column(DateTime(timezone=True), nullable=True)
    last_pull_at   = Column(DateTime(timezone=True), nullable=True)
    records_pushed = Column(Integer, nullable=False, default=0)
    records_pulled = Column(Integer, nullable=False, default=0)
    last_error     = Column(Text, nullable=True)
