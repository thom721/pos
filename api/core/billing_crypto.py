"""
Fernet encryption for billing period dates.

Key derivation: HKDF(SHA-256, ikm=SECRET_KEY, salt=tenant_id, info=b'billing-period')
This ensures that even if one tenant's key is compromised, other tenants' data
remains protected, and dates cannot be swapped between tenants.
"""
import base64
from datetime import datetime
from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from api.core.config import settings


def _derive_fernet(tenant_id: str) -> Fernet:
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=tenant_id.encode("utf-8"),
        info=b"billing-period",
    )
    key_bytes = hkdf.derive(settings.SECRET_KEY.encode("utf-8"))
    return Fernet(base64.urlsafe_b64encode(key_bytes))


def encrypt_date(dt: datetime, tenant_id: str) -> str:
    """Encrypt a naive (Haiti local) datetime to a URL-safe Fernet token string."""
    token = _derive_fernet(tenant_id).encrypt(dt.isoformat().encode("utf-8"))
    return token.decode("utf-8")


def decrypt_date(token: str, tenant_id: str) -> datetime:
    """Decrypt a Fernet token back to a naive (Haiti local) datetime."""
    try:
        iso = _derive_fernet(tenant_id).decrypt(token.encode("utf-8")).decode("utf-8")
        return datetime.fromisoformat(iso)
    except (InvalidToken, ValueError) as exc:
        raise ValueError(f"Impossible de déchiffrer la date de facturation: {exc}") from exc


def try_decrypt_date(token: str | None, tenant_id: str) -> datetime | None:
    """Decrypt if token is present, return None otherwise."""
    if not token:
        return None
    return decrypt_date(token, tenant_id)


# ── Per-register date encryption (keyed by register_id) ──────────────────────

def _derive_register_fernet(register_id: str) -> Fernet:
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=register_id.encode("utf-8"),
        info=b"register-billing",
    )
    key_bytes = hkdf.derive(settings.SECRET_KEY.encode("utf-8"))
    return Fernet(base64.urlsafe_b64encode(key_bytes))


def encrypt_register_date(dt: datetime, register_id: str) -> str:
    """Encrypt a naive (Haiti local) register billing date with its own ID as salt."""
    token = _derive_register_fernet(register_id).encrypt(dt.isoformat().encode("utf-8"))
    return token.decode("utf-8")


def try_decrypt_register_date(token: str | None, register_id: str) -> datetime | None:
    """Decrypt a register date token to a naive (Haiti local) datetime; None if missing or tampered."""
    if not token:
        return None
    try:
        iso = _derive_register_fernet(register_id).decrypt(token.encode("utf-8")).decode("utf-8")
        return datetime.fromisoformat(iso)
    except Exception:
        return None  # token altéré → traité comme absent
