from sqlalchemy import Column, String, Boolean, DateTime
from .base import UUIDBase


class Affiliate(UUIDBase):
    """Compte de parrainage — indépendant du système Tenant/User (sa propre
    auth, son propre login). N'importe qui peut s'inscrire pour obtenir un
    referral_code, à partager via un lien (?ref=CODE sur /register) pour
    toucher une commission sur les tenants ainsi amenés (voir
    AffiliateCommission)."""
    __tablename__ = "affiliates"

    email    = Column(String(255), unique=True, nullable=False, index=True)
    password = Column(String(255), nullable=False)  # hash pwdlib (argon2)
    full_name = Column(String(200), nullable=False)
    phone     = Column(String(50), nullable=True)

    # 8 caractères, alphabet sans 0/O/1/I (voir affiliate_service.generate_referral_code)
    referral_code = Column(String(20), unique=True, nullable=False, index=True)

    is_email_verified = Column(Boolean, nullable=False, default=False)
    email_verification_code       = Column(String(10), nullable=True)
    email_verification_expires_at = Column(DateTime(timezone=False), nullable=True)

    is_active = Column(Boolean, nullable=False, default=True)
