import secrets
import uuid as _uuid

from sqlalchemy import Column, DateTime, ForeignKey, String

from api.models.base import Base
from api.core.dt_coerce import now_local

_SAFE = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I ambiguity


def generate_installation_code() -> str:
    """Generate a human-readable code like ABCD-EFGH-IJKL."""
    return "-".join(
        "".join(secrets.choice(_SAFE) for _ in range(4)) for _ in range(3)
    )


class InstallationCode(Base):
    __tablename__ = "installation_codes"

    id           = Column(String(36), primary_key=True, default=lambda: str(_uuid.uuid4()))
    code         = Column(String(20), unique=True, nullable=False, index=True)
    tenant_id    = Column(String(36), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    warehouse_id = Column(String(36), ForeignKey("warehouses.id", ondelete="CASCADE"), nullable=False)
    created_at   = Column(DateTime(timezone=False), nullable=False, default=now_local)
    # Validity: determined at runtime by warehouse.is_claimed — no stored expiry needed
