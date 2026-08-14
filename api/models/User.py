from sqlalchemy import Column, String, JSON, Boolean, Integer, DateTime, ForeignKey, UniqueConstraint
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
    email    = Column(String(255), nullable=True, unique=True)

    roles       = Column(JSON, nullable=True)
    permissions = Column(JSON, nullable=True)
    password    = Column(String(255), nullable=False)
    offline_hash = Column(String(64), nullable=True)
    must_change_password = Column(Boolean, default=True, nullable=False)
    is_active    = Column(Boolean, default=True, nullable=False)
    # Réinitialisation de mot de passe — code numérique à 6 chiffres, envoyé
    # par email, expire 15 min après génération (voir api/routes/auth.py).
    password_reset_code       = Column(String(10), nullable=True)
    password_reset_expires_at = Column(DateTime, nullable=True)
    # Incrémenté à chaque changement de roles/permissions — comparé au claim
    # "perm_v" du JWT pour forcer une reconnexion quand les droits changent.
    permissions_version = Column(Integer, default=0, nullable=False)

    sales            = relationship("Sale",            back_populates="user")
    purchases        = relationship("Purchase",        back_populates="user")
    payments         = relationship("Payment",         back_populates="user")
    employee_profile = relationship("EmployeeProfile", back_populates="user", uselist=False)

    __table_args__ = (
        UniqueConstraint("username", "tenant_id", name="uq_user_username_tenant"),
        UniqueConstraint("phone",    "tenant_id", name="uq_user_phone_tenant"),
    )
