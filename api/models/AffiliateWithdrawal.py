from sqlalchemy import Column, String, Numeric, Text, DateTime, ForeignKey
from .base import UUIDBase


class AffiliateWithdrawal(UUIDBase):
    """Demande de retrait d'un parrain sur son solde de commissions
    disponibles. Traité manuellement par un superadmin (voir
    api/routes/admin.py :: list/patch affiliate-withdrawals)."""
    __tablename__ = "affiliate_withdrawals"

    affiliate_id = Column(String(36), ForeignKey('affiliates.id'), nullable=False, index=True)
    amount       = Column(Numeric(10, 2), nullable=False)

    # 'pending' -> 'approved' | 'rejected' | 'paid'
    status = Column(String(20), nullable=False, default='pending')

    payout_method = Column(Text, nullable=True)   # texte libre saisi par l'affilié (ex: numéro MonCash)
    admin_note    = Column(Text, nullable=True)

    processed_at = Column(DateTime(timezone=False), nullable=True)
    processed_by = Column(String(255), nullable=True)  # email du superadmin ayant traité la demande
