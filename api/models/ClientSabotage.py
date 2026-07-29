from sqlalchemy import Column, String, Boolean, Text, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.ext.hybrid import hybrid_property
from .base import UUIDBase


class ClientSabotage(UUIDBase):
    __tablename__ = "clients_sabotage"
    __table_args__ = (
        UniqueConstraint('tenant_id', 'account_number', name='uq_client_sabotage_tenant_account'),
        UniqueConstraint('tenant_id', 'telephone', name='uq_client_sabotage_tenant_telephone'),
    )

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),    nullable=True, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'), nullable=True, index=True)

    # Toujours obligatoires — jamais inclus dans les champs configurables du tenant.
    nom       = Column(String(255), nullable=False)
    prenom    = Column(String(255), nullable=False)
    telephone = Column(String(50),  nullable=False)
    adresse   = Column(Text,        nullable=False)

    # Numéro de compte à 6 chiffres, généré serveur (voir sabotage_service.generate_account_number),
    # unique par tenant (comme le téléphone).
    account_number = Column(String(6), nullable=False)

    # Champs additionnels configurés par le tenant (AppConfig.client_sabotage_fields) —
    # JSON {label: valeur}. Ne contient jamais nom/prenom/telephone/adresse.
    extra_fields = Column(Text, nullable=True)

    is_active = Column(Boolean, default=True, nullable=False)

    depots = relationship("Depot", back_populates="client")
    retraits = relationship("Retrait", back_populates="client")

    @hybrid_property
    def balance(self):
        total_depot = sum((d.amount for d in self.depots), 0)
        total_retrait = sum((r.amount for r in self.retraits), 0)
        return total_depot - total_retrait
