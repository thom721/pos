"""
Public routes — no authentication required.
Used by the Flutter Web registration/login flow and WordPress webhook.
"""
import base64
import os
import logging

from fastapi import APIRouter, Depends, HTTPException, Query
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


@router.get("/pricing")
def get_pricing(db: Session = Depends(get_db)):
    """
    Returns public pricing info from platform_config (no auth required).
    Used by the public landing page to display up-to-date prices and trial days.
    """
    from api.models.PlatformConfig import PlatformConfig
    cfg = db.query(PlatformConfig).first()
    if not cfg:
        return {
            "monthly_price_htg": 2500.00,
            "monthly_price_usd": 20.00,
            "trial_days": 30,
            "price_per_extra_caisse_htg": 500.00,
            "price_per_extra_caisse_usd": 4.00,
        }
    return {
        "monthly_price_htg":         float(cfg.monthly_price_htg),
        "monthly_price_usd":         float(cfg.monthly_price_usd),
        "trial_days":                cfg.trial_days,
        "price_per_extra_caisse_htg": float(cfg.price_per_extra_caisse_htg),
        "price_per_extra_caisse_usd": float(cfg.price_per_extra_caisse_usd),
    }


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
