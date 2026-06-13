import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, DateTime 
from api.database import Base

class UUIDBase(Base):
    __abstract__ = True

    id = Column(
        String(36),
        primary_key=True,
        default=lambda: str(uuid.uuid4())
    )

    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )

    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False
    )
