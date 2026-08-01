from sqlalchemy import Column, String, Numeric, Enum, ForeignKey, Index, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.ext.hybrid import hybrid_property
import enum
from .base import UUIDBase


class SaleStatus(enum.Enum):
    unpaid    = "UNPAID"
    paid      = "PAID"
    partial   = "PARTIAL"
    cancelled = "CANCELLED"
    credit    = "CREDIT"
    pending   = "PENDING"


class Sale(UUIDBase):
    __tablename__ = "sales"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    customer_id  = Column(String(36), ForeignKey("customers.id"), nullable=True)
    user_id      = Column(String(36), ForeignKey("users.id"))
    warehouse_id = Column(String(36), ForeignKey("warehouses.id"), nullable=True, index=True)
    reference    = Column(String(255), nullable=False)
    total_amount = Column(Numeric(12, 2), nullable=False)
    discount     = Column(Numeric(12, 2), default=0, nullable=False)
    discount_id  = Column(String(36), ForeignKey("discounts.id"), nullable=True)
    final_amount = Column(Numeric(12, 2), default=0)
    paid_amount  = Column(Numeric(12, 2), default=0)
    # Montants de fidélisation réellement appliqués à CETTE vente (figés à la
    # création, indépendants du taux courant) — permettent une annulation
    # symétrique exacte dans cancel_sale, même si AppConfig.loyalty_percent
    # change entre-temps.
    loyalty_earned   = Column(Numeric(12, 2), nullable=False, default=0)
    loyalty_redeemed = Column(Numeric(12, 2), nullable=False, default=0)
    # Solde de fidélité du client APRÈS cette vente (figé à la création) —
    # permet d'afficher "Solde fidélité: X" sur le reçu (cumul, pas seulement
    # le gain/usage de cette vente) même en cas de réimpression ultérieure,
    # sans dépendre du solde courant du client qui continue d'évoluer.
    customer_loyalty_balance = Column(Numeric(12, 2), nullable=True)
    # Monnaie rendue au client (paid_amount reste plafonné au montant dû —
    # voir create_sale — donc l'excédent remis en espèces serait sinon perdu
    # et absent du reçu).
    change_due       = Column(Numeric(12, 2), nullable=False, default=0)
    status       = Column(
        Enum(SaleStatus, values_callable=lambda obj: [e.value for e in obj]),
        default=SaleStatus.unpaid,
    )

    customer        = relationship("Customer",  back_populates="sales")
    user            = relationship("User",      back_populates="sales")
    warehouse       = relationship("Warehouse", back_populates="sales")
    items           = relationship("SaleItem",  back_populates="sale")
    discount_catalog = relationship("Discount", foreign_keys=[discount_id])

    payments = relationship(
        "Payment",
        primaryjoin=(
            "and_("
            "foreign(Payment.reference_id) == Sale.id, "
            "Payment.reference_type == 'SALE'"
            ")"
        ),
        foreign_keys="[Payment.reference_id]",
        back_populates="sale",
        viewonly=True,
    )

    debts = relationship(
        "Debt",
        primaryjoin=(
            "and_("
            "foreign(Debt.reference_id) == Sale.id, "
            "Debt.reference_type == 'SALE'"
            ")"
        ),
        foreign_keys="[Debt.reference_id]",
        back_populates="sale",
        viewonly=True,
    )

    __table_args__ = (
        UniqueConstraint("reference", "tenant_id", name="uq_sale_ref_tenant"),
        Index("idx_sale_customer_id", "customer_id"),
        Index("idx_sale_status",      "status"),
        Index("idx_sale_created_at",  "created_at"),
    )

    @hybrid_property
    def balance(self):
        return self.final_amount - self.paid_amount
