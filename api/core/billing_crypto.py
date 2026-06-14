"""
Fernet encryption for billing period dates.

Key derivation: HKDF(SHA-256, ikm=SECRET_KEY, salt=tenant_id, info=b'billing-period')
This ensures that even if one tenant's key is compromised, other tenants' data
remains protected, and dates cannot be swapped between tenants.
"""
import base64
from datetime import datetime, timezone
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
    """Encrypt a datetime to a URL-safe Fernet token string."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    token = _derive_fernet(tenant_id).encrypt(dt.isoformat().encode("utf-8"))
    return token.decode("utf-8")


def decrypt_date(token: str, tenant_id: str) -> datetime:
    """Decrypt a Fernet token back to a datetime (UTC-aware)."""
    try:
        iso = _derive_fernet(tenant_id).decrypt(token.encode("utf-8")).decode("utf-8")
        dt = datetime.fromisoformat(iso)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except (InvalidToken, ValueError) as exc:
        raise ValueError(f"Impossible de déchiffrer la date de facturation: {exc}") from exc


def try_decrypt_date(token: str | None, tenant_id: str) -> datetime | None:
    """Decrypt if token is present, return None otherwise."""
    if not token:
        return None
    return decrypt_date(token, tenant_id)
