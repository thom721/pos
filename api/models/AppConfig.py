from sqlalchemy import ForeignKey, Column, String, Numeric, Boolean, Text
from .base import UUIDBase

class AppConfig(UUIDBase):
    """Single-row global config — use config_service.get_or_create() to access."""
    __tablename__ = "app_config"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    # Business identity (shared across devices)
    business_name   = Column(String(200), default='Mon Commerce')
    phone           = Column(String(50),  default='')
    email           = Column(String(200), default='')
    address         = Column(Text,        default='')
    logo_path       = Column(String(500), default='')

    # Operational settings
    business_type   = Column(String(50),  default='commerce')
    currency        = Column(String(10),  default='HTG')
    currency_symbol = Column(String(10),  default='HTG ')
    # Exchange rates: 1 foreign unit = X HTG (taux du jour)
    rate_usd        = Column(Numeric(12, 4), default=130.0)
    rate_eur        = Column(Numeric(12, 4), default=140.0)
    tax_rate        = Column(Numeric(5, 2),  default=0.0)
    show_tax        = Column(Boolean, default=False)
    receipt_footer  = Column(Text, default='Merci pour votre achat !')

    # Printer configuration
    pos_printer_name = Column(String(500), nullable=False, default='')
    pos_auto_print   = Column(Boolean,     nullable=False, default=False)
    doc_printer_name = Column(String(500), nullable=False, default='')
    doc_auto_print   = Column(Boolean,     nullable=False, default=False)
