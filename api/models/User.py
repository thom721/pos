from sqlalchemy import Column, String, JSON, Boolean, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from .base import UUIDBase

class User(UUIDBase):
    __tablename__ = "users"
    tenant_id    = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)
    # Tableau JSON des UUID de dépôts autorisés. NULL = accès à tous les dépôts.
    warehouse_id = Column(JSON, nullable=True)

    fname    = Column(String(255), nullable=False)
    lname    = Column(String(255), nullable=False)
    username = Column(String(255), index=True, nullable=False)
    phone    = Column(String(255), index=True, nullable=True)
    address  = Column(String(255))
    email    = Column(String(255), nullable=True)

    roles       = Column(JSON, nullable=True)
    permissions = Column(JSON, nullable=True)
    password    = Column(String(255), nullable=False)
    offline_hash = Column(String(64), nullable=True)
    must_change_password = Column(Boolean, default=True, nullable=False)
    is_active    = Column(Boolean, default=True, nullable=False)

    sales            = relationship("Sale",            back_populates="user")
    purchases        = relationship("Purchase",        back_populates="user")
    payments         = relationship("Payment",         back_populates="user")
    employee_profile = relationship("EmployeeProfile", back_populates="user", uselist=False)

    __table_args__ = (
        UniqueConstraint("username", "tenant_id", name="uq_user_username_tenant"),
        UniqueConstraint("email",    "tenant_id", name="uq_user_email_tenant"),
        UniqueConstraint("phone",    "tenant_id", name="uq_user_phone_tenant"),
    )
