from sqlalchemy import Column, String, Text, ForeignKey, Index
from .base import UUIDBase


class AuditLog(UUIDBase):
    __tablename__ = "audit_logs"

    tenant_id     = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)
    user_id       = Column(String(36), ForeignKey('users.id'),   nullable=True)
    action        = Column(String(50),  nullable=False)    # CREATE UPDATE DELETE CANCEL LOGIN
    resource_type = Column(String(50),  nullable=False)    # sale product user stock ...
    resource_id   = Column(String(100), nullable=True)
    detail        = Column(Text,        nullable=True)
    ip_address    = Column(String(45),  nullable=True)

    __table_args__ = (
        Index("idx_audit_tenant_created", "tenant_id", "created_at"),
        Index("idx_audit_resource",       "resource_type", "resource_id"),
    )
