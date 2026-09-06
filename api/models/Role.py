from sqlalchemy import ForeignKey, Column, String, Boolean, JSON, UniqueConstraint
from .base import UUIDBase


class Role(UUIDBase):
    """tenant_id NULL = défaut plateforme (rôle intégré partagé tant qu'aucun
    tenant ne l'a "forké") ou rôle purement local (install self-hosted sans
    tenant cloud). tenant_id renseigné = surcharge propre à CE tenant — soit
    un fork d'un rôle intégré (is_builtin=True, créé au premier PUT sur ce
    rôle par ce tenant, voir api/routes/roles.py update_role), soit un rôle
    personnalisé (is_builtin=False) créé par ce tenant. Unicité par
    (tenant_id, name), PAS par name seul — sans quoi deux tenants ne
    pourraient jamais avoir chacun un rôle "manager" ou un rôle personnalisé
    du même nom (voir migration one-shot _repair_role_uniqueness, api/main.py)."""
    __tablename__ = "roles"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    name        = Column(String(100), nullable=False, index=True)
    label       = Column(String(200), nullable=False)
    color       = Column(String(20),  nullable=True)   # hex color, ex: "#7C3AED"
    is_builtin  = Column(Boolean, default=True, nullable=False)
    permissions = Column(JSON, nullable=True)           # list[str] or ["all"]

    __table_args__ = (
        UniqueConstraint('tenant_id', 'name', name='uq_role_tenant_name'),
    )
