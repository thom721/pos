from sqlalchemy import Column, String, Integer, Numeric, ForeignKey, UniqueConstraint
from .base import UUIDBase


class AffiliateCommission(UUIDBase):
    """Ledger append-only — une ligne par renouvellement de caisse commissionné.
    Le rang de la caisse (register_rank, ordre de création chez ce tenant) est
    figé une fois déterminé et détermine le taux appliqué à CHAQUE renouvellement
    (voir affiliate_service.commission_rate_for_rank : 20%/16%/12.8%/10.24%/
    8.192% pour les rangs 1-5, 0% au-delà — plafond fixe, pas un seuil de %).

    UniqueConstraint(billing_payment_id, register_id) : rend le hook dans
    confirm_payment() idempotent si jamais rejoué sur le même paiement."""
    __tablename__ = "affiliate_commissions"

    affiliate_id       = Column(String(36), ForeignKey('affiliates.id'), nullable=False, index=True)
    tenant_id          = Column(String(36), ForeignKey('tenants.id'), nullable=False, index=True)
    register_id        = Column(String(36), ForeignKey('pos_registers.id'), nullable=False, index=True)
    billing_payment_id = Column(String(36), ForeignKey('billing_payments.id'), nullable=False, index=True)

    register_rank    = Column(Integer, nullable=False)
    commission_rate  = Column(Numeric(6, 5), nullable=False)
    base_amount      = Column(Numeric(10, 2), nullable=False)   # prix de la caisse pour ce renouvellement
    commission_amount = Column(Numeric(10, 2), nullable=False)  # base_amount * commission_rate

    # 'available' = compte dans le solde retirable ; 'withdrawn' = déjà couvert
    # par un retrait marqué payé (voir AffiliateWithdrawal).
    status = Column(String(20), nullable=False, default='available')

    __table_args__ = (
        UniqueConstraint('billing_payment_id', 'register_id', name='uq_affiliate_commission_payment_register'),
    )
