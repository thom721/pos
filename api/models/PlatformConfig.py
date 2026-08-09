from sqlalchemy import Column, String, Integer, Numeric, Boolean, Text
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
    support_address   = Column(String(255), nullable=False, default='')
    # 'manual' = instructions manuelles | 'api' = traitement automatique via API
    moncash_mode      = Column(String(10),  nullable=False, default='manual')
    natcash_mode      = Column(String(10),  nullable=False, default='manual')
    # Superadmin credentials — stored in DB for cloud/Docker persistence
    admin_email         = Column(String(200), nullable=False, default='')
    admin_password_hash = Column(String(255), nullable=False, default='')

    # Prix par caisse supplémentaire (au-delà du max_caisses du plan)
    price_per_extra_caisse_htg = Column(Numeric(10, 2), nullable=False, default=500.00)
    price_per_extra_caisse_usd = Column(Numeric(10, 2), nullable=False, default=4.00)

    # Prix par dépôt supplémentaire (au-delà du max_depots du plan)
    price_per_extra_depot_htg = Column(Numeric(10, 2), nullable=False, default=500.00)
    price_per_extra_depot_usd = Column(Numeric(10, 2), nullable=False, default=4.00)

    # SMTP — pour les notifications d'expiration de plan
    smtp_host     = Column(String(200), nullable=False, default='')
    smtp_port     = Column(Integer,     nullable=False, default=587)
    smtp_user     = Column(String(200), nullable=False, default='')
    smtp_password = Column(String(255), nullable=False, default='')
    smtp_from     = Column(String(200), nullable=False, default='')

    # Statistiques affichées sur la page d'accueil publique (éditables par le superadmin)
    stat_businesses       = Column(String(30), nullable=False, default='500+')
    stat_transactions_day = Column(String(30), nullable=False, default='10k+')
    stat_uptime           = Column(String(30), nullable=False, default='99.9%')

    # Cards de tarification affichées sur la page publique (JSON array)
    pricing_plans_json    = Column(Text, nullable=True, default=None)
    logo_url              = Column(String(512), nullable=True, default=None)

    # ── Facturation ─────────────────────────────────────────────────────────────
    # Si True : les jours d'essai sont inclus dans le premier mois payé
    # (l'abonnement démarre à la date de création, pas à la date de paiement).
    # Si False (défaut) : l'essai est offert, le mois payé commence au paiement.
    trial_included_in_billing = Column(Boolean, nullable=False, default=False)

    # Rabais plan annuel (%) — appliqué sur prix_mensuel × 12
    # Ex : annual_discount_pct=20 → prix annuel = mensuel × 12 × 0.80
    annual_discount_pct = Column(Integer, nullable=False, default=20)

    # ── Méthodes de paiement activées ───────────────────────────────────────────
    # False = méthode désactivée (grisée côté client, refusée côté serveur).
    cash_enabled    = Column(Boolean, nullable=False, default=True)
    moncash_enabled = Column(Boolean, nullable=False, default=True)
    natcash_enabled = Column(Boolean, nullable=False, default=True)
    card_enabled    = Column(Boolean, nullable=False, default=True)

    # ── Mises à jour applicatives ────────────────────────────────────────────
    latest_version = Column(String(20),  nullable=False, default='0.9.0')
    latest_build   = Column(Integer,     nullable=False, default=1)
    update_notes   = Column(Text,        nullable=True,  default=None)
    update_url         = Column(String(512), nullable=True,  default=None)
    update_url_android = Column(String(512), nullable=True,  default=None)
    force_update       = Column(Boolean,     nullable=False, default=False)
