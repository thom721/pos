from sqlalchemy import Column, String, Integer, Numeric, Boolean
from .base import UUIDBase

class PlatformConfig(UUIDBase):
    """Single-row platform-wide configuration (singleton)."""
    __tablename__ = "platform_config"

    moncash_number    = Column(String(30),  nullable=False, default='')
    natcash_number    = Column(String(30),  nullable=False, default='')
    monthly_price_htg = Column(Numeric(10, 2), nullable=False, default=1500.00)
    monthly_price_usd = Column(Numeric(10, 2), nullable=False, default=12.00)
    stripe_price_id   = Column(String(100), nullable=False, default='')
    trial_days        = Column(Integer,     nullable=False, default=30)
    support_email     = Column(String(200), nullable=False, default='')
    support_whatsapp  = Column(String(30),  nullable=False, default='')
    # 'manual' = instructions manuelles | 'api' = traitement automatique via API
    moncash_mode      = Column(String(10),  nullable=False, default='manual')
    natcash_mode      = Column(String(10),  nullable=False, default='manual')
    # Superadmin credentials — stored in DB for cloud/Docker persistence
    admin_email         = Column(String(200), nullable=False, default='')
    admin_password_hash = Column(String(255), nullable=False, default='')
