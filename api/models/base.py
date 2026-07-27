import uuid
from sqlalchemy import Column, String, DateTime
from api.database import Base
from api.core.dt_coerce import now_local


class UUIDBase(Base):
    __abstract__ = True

    id = Column(
        String(36),
        primary_key=True,
        default=lambda: str(uuid.uuid4())
    )

    created_at = Column(
        DateTime(timezone=False),
        default=now_local,
        nullable=False
    )

    updated_at = Column(
        DateTime(timezone=False),
        default=now_local,
        onupdate=now_local,
        nullable=False
    )
