from sqlalchemy import ForeignKey, Column, String, Boolean, JSON
from .base import UUIDBase


class Role(UUIDBase):
    __tablename__ = "roles"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    name        = Column(String(100), unique=True, nullable=False, index=True)
    label       = Column(String(200), nullable=False)
    color       = Column(String(20),  nullable=True)   # hex color, ex: "#7C3AED"
    is_builtin  = Column(Boolean, default=True, nullable=False)
    permissions = Column(JSON, nullable=True)           # list[str] or ["all"]
