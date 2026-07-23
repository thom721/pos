import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, DateTime
from sqlalchemy.types import TypeDecorator
from api.database import Base


class UTCDateTime(TypeDecorator):
    """DateTime qui attache toujours tzinfo=UTC à la lecture depuis MySQL.

    MySQL DATETIME + PyMySQL retourne des datetimes naïfs. Pydantic v2
    sérialise un datetime naïf sans 'Z', ce qui fait que Flutter le
    parse comme heure locale plutôt qu'UTC. Ce TypeDecorator corrige ça :
    toute valeur lue depuis la DB est garantie timezone-aware (UTC).
    """
    impl = DateTime(timezone=True)
    cache_ok = True

    def process_result_value(self, value, dialect):
        if value is not None and value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value


class UUIDBase(Base):
    __abstract__ = True

    id = Column(
        String(36),
        primary_key=True,
        default=lambda: str(uuid.uuid4())
    )

    created_at = Column(
        UTCDateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )

    updated_at = Column(
        UTCDateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False
    )
