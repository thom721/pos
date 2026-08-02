from sqlalchemy import ForeignKey, Column, String, Text, Numeric
from sqlalchemy.orm import relationship
from sqlalchemy.ext.hybrid import hybrid_property
from .base import UUIDBase

class Customer(UUIDBase):
    __tablename__ = "customers"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    # name = nom de famille seul depuis l'ajout de fname (avant : nom complet
    # en un seul champ) — les clients existants gardent leur valeur telle
    # quelle dans name, fname vide (aucun découpage rétroactif tenté).
    fname = Column(String(255), nullable=True, default='')
    name = Column(String(255), nullable=False)
    nif = Column(String(50), nullable=True)   # NIF ou CIN — évite les conflits de nom
    phone = Column(String(50), nullable=False)
    email = Column(String(255), nullable=True)
    address = Column(Text, nullable=False)
    credit_limit = Column(Numeric(12, 2), default=0)

    # Solde de fidélisation — crédit accumulé (% du montant des ventes,
    # voir AppConfig.loyalty_percent), utilisable comme moyen de paiement sur
    # une vente future. Distinct de credit_limit (plafond de dette autorisée).
    loyalty_balance = Column(Numeric(12, 2), nullable=False, default=0)

    sales = relationship("Sale", back_populates="customer")

    # debt = relationship("Debt", back_populates="customer")

    debts = relationship(
        "Debt",
        primaryjoin=(
            "and_("
            "foreign(Debt.partner_id) == Customer.id, "
            "Debt.partner_type == 'CUSTOMER'"
            ")"
        ),
        foreign_keys="[Debt.partner_id]",
        viewonly=True
    )

    @hybrid_property
    def balance(self):
        # loyalty_redeemed compte comme payé (voir sale_service.create_sale) —
        # l'ignorer ferait apparaître la portion réglée en fidélité comme
        # encore due.
        return sum(
            (s.final_amount or s.total_amount) - (s.paid_amount or 0) - (s.loyalty_redeemed or 0)
            for s in self.sales
        )

    @hybrid_property
    def full_name(self):
        return f"{self.fname} {self.name}".strip() if self.fname else self.name
