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

# Secret fixe, partagé par TOUTES les installations (cloud et locales),
# indépendant de settings.SECRET_KEY (qui lui est propre à chaque
# installation — généré aléatoirement par le script Windows — car il
# sert à signer les JWT et ne doit jamais être partagé entre serveurs).
#
# PosRegister.trial_ends_at / subscription_started_at / subscription_ends_at
# sont synchronisés entre le cloud et les installations locales
# (SYNC_ENTITIES, direction "both"). Si ces dates étaient chiffrées avec
# settings.SECRET_KEY, un serveur ne pourrait jamais déchiffrer une date
# chiffrée par un AUTRE serveur (secret différent) — le déchiffrement
# échoue silencieusement et la date apparaît comme absente (voir
# try_decrypt_register_date). Ce secret fixe résout ce problème : son but
# est seulement d'empêcher une modification directe et triviale en base
# (UPDATE SQL manuel), pas de résister à un attaquant ayant accès au code.
_REGISTER_DATE_MASTER_KEY = "91a9a4be1ab17b6a11514083dac3660d1a4860f46a52606f3bb6987611913bd4"


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
    key_bytes = hkdf.derive(_REGISTER_DATE_MASTER_KEY.encode("utf-8"))
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


# ── Migration one-shot : ancien schéma (clé = settings.SECRET_KEY) ───────────
# Utilisé uniquement par le correctif de démarrage qui re-chiffre les dates
# existantes vers _REGISTER_DATE_MASTER_KEY (voir main.py). Ne pas utiliser
# ailleurs — try_decrypt_register_date/encrypt_register_date sont la seule
# API valable pour tout nouveau code.
def _derive_register_fernet_legacy(register_id: str) -> Fernet:
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=register_id.encode("utf-8"),
        info=b"register-billing",
    )
    key_bytes = hkdf.derive(settings.SECRET_KEY.encode("utf-8"))
    return Fernet(base64.urlsafe_b64encode(key_bytes))


def try_decrypt_register_date_legacy(token: str | None, register_id: str) -> datetime | None:
    """Déchiffre avec l'ancien schéma (clé = settings.SECRET_KEY de CE serveur).
    Utilisé uniquement pour migrer les données créées avant le passage à la
    clé fixe partagée — voir _migrate_register_dates_to_shared_key (main.py).
    """
    if not token:
        return None
    try:
        iso = _derive_register_fernet_legacy(register_id).decrypt(token.encode("utf-8")).decode("utf-8")
        return datetime.fromisoformat(iso)
    except Exception:
        return None
