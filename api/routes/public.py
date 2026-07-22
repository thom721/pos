"""
Public routes — no authentication required.
Used by the Flutter Web registration/login flow and WordPress webhook.
"""
import base64
import html
import json
import os
import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session

from api.database import get_db
from api.schemas.tenant import TenantRegister, CloudLogin, CloudToken, TenantRead
from api.services.tenant_service import register_tenant, cloud_login

router = APIRouter(prefix="/api/public", tags=["Public"])
_log = logging.getLogger("pos.public")

# ── Server identity (Ed25519) ─────────────────────────────────────────────────

def _load_identity_key():
    """Load Ed25519 private key from settings (pos_server.ini > env > default)."""
    from api.core.config import settings
    raw = settings.IDENTITY_PRIVATE_KEY or os.getenv("IDENTITY_PRIVATE_KEY", "")
    if not raw:
        return None, None
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from cryptography.hazmat.primitives.serialization import (
            Encoding, PublicFormat, PrivateFormat, NoEncryption,
        )
        key_bytes = base64.b64decode(raw)
        priv = Ed25519PrivateKey.from_private_bytes(key_bytes)
        pub  = priv.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
        return priv, pub
    except Exception as exc:
        _log.warning("IDENTITY_PRIVATE_KEY invalide : %s", exc)
        return None, None

_IDENTITY_PRIVATE_KEY, _IDENTITY_PUBLIC_KEY = _load_identity_key()
_APP_NAME = "pos-connect-saas"


@router.get("/identity")
def server_identity(nonce: str = Query(..., min_length=8, max_length=64)):
    """
    Returns a signed proof-of-identity.
    The Flutter wizard calls this with a random nonce; the server signs
    "pos-connect-saas:{nonce}" with its Ed25519 private key.
    The app verifies with the public key compiled into the binary.
    """
    if _IDENTITY_PRIVATE_KEY is None:
        raise HTTPException(503, "Identité serveur non configurée (IDENTITY_PRIVATE_KEY manquant)")

    message   = f"{_APP_NAME}:{nonce}".encode()
    signature = _IDENTITY_PRIVATE_KEY.sign(message)

    return {
        "app":       _APP_NAME,
        "signature": base64.b64encode(signature).decode(),
    }


@router.post("/register", status_code=201)
def register(payload: TenantRegister, db: Session = Depends(get_db)):
    """
    Creates a new tenant + admin user.
    Called from Flutter Web registration screen or WordPress page.
    The tenant starts with status='trial' (30-day free trial).
    Payment webhooks transition status to 'active'.
    """
    tenant, user = register_tenant(
        db,
        business_name=payload.business_name,
        owner_email=payload.owner_email,
        password=payload.password,
        phone=payload.phone,
    )
    from api.models.PlatformConfig import PlatformConfig as _PC
    cfg = db.query(_PC).first()
    trial_days = cfg.trial_days if cfg else 30
    return {
        "message": f"Compte créé avec succès. Période d'essai de {trial_days} jours activée.",
        "tenant_id": tenant.id,
        "slug": tenant.slug,
        "trial_ends_at": tenant.trial_ends_at,
    }


@router.post("/login", response_model=CloudToken)
def login(payload: CloudLogin, db: Session = Depends(get_db)):
    """
    Cloud login by email + password.
    Returns JWT containing tenant_id for all subsequent requests.
    Registers the device (pos_register) on first login of a new device_id.
    """
    return cloud_login(
        db,
        email=payload.email,
        password=payload.password,
        device_id=payload.device_id,
        register_name=payload.register_name,
    )


_DEFAULT_PLANS = [
    {
        "id": "starter",
        "visible": True,
        "name": "Starter",
        "subtitle": "Pour découvrir",
        "price_htg": "Gratuit",
        "price_usd": None,
        "period": "{trial_days} jours d'essai",
        "highlighted": False,
        "features": [
            "1 dépôt", "1 caisse", "Ventes & encaissements",
            "Gestion clients", "Rapports de base", "Support email", "Aucune carte requise",
        ],
    },
    {
        "id": "pro",
        "visible": True,
        "name": "Pro",
        "subtitle": "Basé sur le nombre de caisses",
        "price_htg": None,
        "price_usd": None,
        "period": "par mois · 1 dépôt",
        "highlighted": True,
        "features": [
            "1 dépôt inclus", "3 caisses incluses", "Mode restaurant",
            "Sync cloud temps réel", "Rapports avancés", "Multi-plateformes", "Support prioritaire",
        ],
    },
    {
        "id": "enterprise",
        "visible": True,
        "name": "Enterprise",
        "subtitle": "Pour les grandes enseignes",
        "price_htg": "Sur devis",
        "price_usd": None,
        "period": "",
        "highlighted": False,
        "features": [
            "Dépôts illimités", "Caisses illimitées", "API REST complète",
            "White label", "Formation sur site", "Gestionnaire dédié", "SLA 99.9%",
        ],
    },
]


def _resolve_plans(plans: list, price_htg: float, price_usd: float, trial_days: int) -> list:
    """Replace dynamic placeholders in plan data."""
    def _fmt_htg(v: float) -> str:
        return f"{int(v) if v == int(v) else v:,} HTG".replace(",", " ")

    def _fmt_usd(v: float) -> str:
        return f"{int(v) if v == int(v) else v} USD"

    result = []
    for plan in plans:
        if not plan.get("visible", True):
            continue
        p = dict(plan)
        # Resolve dynamic prices (None = use monthly price from config)
        if p.get("price_htg") is None:
            p["price_htg"] = _fmt_htg(price_htg)
        if p.get("price_usd") is None and plan["id"] == "pro":
            p["price_usd"] = _fmt_usd(price_usd)
        else:
            p["price_usd"] = p.get("price_usd") or ""
        # Replace trial_days placeholder in period
        period = p.get("period", "")
        if "{trial_days}" in period:
            p["period"] = period.replace("{trial_days}", str(trial_days))
        result.append(p)
    return result


@router.get("/pricing")
def get_pricing(db: Session = Depends(get_db)):
    """
    Returns public pricing info from platform_config (no auth required).
    Used by the public landing page to display up-to-date prices and trial days.
    """
    from api.models.PlatformConfig import PlatformConfig
    cfg = db.query(PlatformConfig).first()

    price_htg   = float(cfg.monthly_price_htg)   if cfg else 2500.0
    price_usd   = float(cfg.monthly_price_usd)   if cfg else 20.0
    trial_days  = cfg.trial_days                  if cfg else 30
    extra_c_htg = float(cfg.price_per_extra_caisse_htg) if cfg else 500.0
    extra_c_usd = float(cfg.price_per_extra_caisse_usd) if cfg else 4.0

    raw_plans = None
    if cfg:
        raw = getattr(cfg, "pricing_plans_json", None)
        if raw:
            try:
                raw_plans = json.loads(raw)
            except (ValueError, TypeError):
                raw_plans = None

    plans = _resolve_plans(raw_plans or _DEFAULT_PLANS, price_htg, price_usd, trial_days)

    return {
        "monthly_price_htg":          price_htg,
        "monthly_price_usd":          price_usd,
        "trial_days":                 trial_days,
        "price_per_extra_caisse_htg": extra_c_htg,
        "price_per_extra_caisse_usd": extra_c_usd,
        "stat_businesses":       getattr(cfg, "stat_businesses",       "500+") if cfg else "500+",
        "stat_transactions_day": getattr(cfg, "stat_transactions_day", "10k+") if cfg else "10k+",
        "stat_uptime":           getattr(cfg, "stat_uptime",           "99.9%") if cfg else "99.9%",
        "plans": plans,
    }


@router.get("/contact-info")
def get_contact_info(db: Session = Depends(get_db)):
    """
    Returns public contact information from platform_config (no auth required).
    Used by the public contact page.
    """
    from api.models.PlatformConfig import PlatformConfig
    cfg = db.query(PlatformConfig).first()
    return {
        "email":    cfg.support_email    if cfg and cfg.support_email    else "support@pos-connect.ht",
        "whatsapp": cfg.support_whatsapp if cfg and cfg.support_whatsapp else "",
        "address":  cfg.support_address  if cfg and cfg.support_address  else "",
    }


class ContactMessage(BaseModel):
    name:    str
    email:   EmailStr
    subject: str
    message: str


@router.post("/contact")
def send_contact_message(body: ContactMessage, db: Session = Depends(get_db)):
    """
    Envoie un message de contact par email via le SMTP configuré dans platform_config.
    """
    from api.models.PlatformConfig import PlatformConfig
    cfg = db.query(PlatformConfig).first()

    smtp_host = getattr(cfg, "smtp_host", "") if cfg else ""
    smtp_port = getattr(cfg, "smtp_port", 587) if cfg else 587
    smtp_user = getattr(cfg, "smtp_user", "") if cfg else ""
    smtp_pass = getattr(cfg, "smtp_password", "") if cfg else ""
    smtp_from = getattr(cfg, "smtp_from", "") if cfg else ""
    to_email  = getattr(cfg, "support_email", "") if cfg else ""

    if not smtp_host or not to_email:
        raise HTTPException(
            status_code=503,
            detail="Service de messagerie non configuré. Contactez-nous directement par email.",
        )

    sender = smtp_from or smtp_user or "noreply@pos-connect.ht"

    msg = MIMEMultipart("alternative")
    msg["Subject"] = f"[Contact POS Connect] {body.subject}"
    msg["From"]    = sender
    msg["To"]      = to_email
    msg["Reply-To"] = body.email

    name_esc    = html.escape(body.name)
    email_esc   = html.escape(body.email)
    subject_esc = html.escape(body.subject)
    msg_esc     = html.escape(body.message).replace("\n", "<br>")

    plain = (
        f"Nom : {body.name}\n"
        f"Email : {body.email}\n"
        f"Sujet : {body.subject}\n\n"
        f"Message :\n{body.message}"
    )
    html_body = f"""
<html><body style="font-family:sans-serif;color:#1A202C;max-width:600px;margin:auto">
  <h2 style="color:#0077C5">Nouveau message de contact</h2>
  <table cellpadding="6" style="border-collapse:collapse">
    <tr><td><strong>Nom :</strong></td><td>{name_esc}</td></tr>
    <tr><td><strong>Email :</strong></td><td><a href="mailto:{email_esc}">{email_esc}</a></td></tr>
    <tr><td><strong>Sujet :</strong></td><td>{subject_esc}</td></tr>
  </table>
  <hr style="margin:20px 0;border:none;border-top:1px solid #E2E8F0">
  <h3>Message :</h3>
  <p style="line-height:1.6">{msg_esc}</p>
</body></html>
"""
    msg.attach(MIMEText(plain, "plain", "utf-8"))
    msg.attach(MIMEText(html_body, "html", "utf-8"))

    try:
        import ssl as _ssl
        if smtp_port == 465:
            # Connexion SSL directe
            ctx = _ssl.create_default_context()
            with smtplib.SMTP_SSL(smtp_host, smtp_port, context=ctx, timeout=15) as srv:
                if smtp_user and smtp_pass:
                    srv.login(smtp_user, smtp_pass)
                srv.sendmail(sender, [to_email], msg.as_string())
        else:
            # STARTTLS (port 587 ou autre)
            with smtplib.SMTP(smtp_host, smtp_port, timeout=15) as srv:
                srv.ehlo()
                try:
                    srv.starttls()
                    srv.ehlo()
                except smtplib.SMTPException:
                    pass  # serveur sans STARTTLS (port 25)
                if smtp_user and smtp_pass:
                    srv.login(smtp_user, smtp_pass)
                srv.sendmail(sender, [to_email], msg.as_string())
        _log.info("Contact message sent from %s to %s", body.email, to_email)
        return {"success": True}
    except Exception as exc:
        _log.error("Erreur envoi email contact: %s", exc)
        raise HTTPException(
            status_code=500,
            detail=f"Erreur lors de l'envoi : {exc}",
        )


@router.get("/tenant/{tenant_id}", response_model=TenantRead)
def get_tenant_info(tenant_id: str, db: Session = Depends(get_db)):
    """
    Returns public tenant info (used by the app to verify trial/active status).
    """
    from api.models.Tenant import Tenant
    from fastapi import HTTPException, status
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not tenant:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Tenant introuvable")
    return tenant
