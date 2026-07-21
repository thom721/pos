"""
Tenant context helpers for multi-tenant (SaaS) mode.

In local mode: tenant_id is absent from JWT → get_current_tenant() returns None.
In cloud mode: tenant_id is in the JWT → get_current_tenant() returns the Tenant row.
"""
from datetime import datetime, timezone, timedelta

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from jose import jwt, JWTError

from api.database import get_db
from api.core.config import settings
from api.models.Tenant import Tenant

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token", auto_error=False)

GRACE_DAYS = 10   # jours après expiration avant le blocage définitif
WARN_DAYS  = 5    # jours avant expiration où l'avertissement est actif

_SUSPENDED_MSG = (
    "Votre abonnement est suspendu ou expiré. "
    "Veuillez renouveler votre abonnement sur posconnect.ht"
)
_GRACE_MSG = (
    "Votre période d'essai est terminée. "
    "Vous disposez d'une période de grâce de 10 jours pour renouveler."
)
_SALES_BLOCKED_MSG = (
    "La création de ventes est bloquée : votre abonnement est expiré. "
    "Renouvelez sur posconnect.ht pour continuer."
)


def _decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        return {}


def _effective_expiry(tenant: Tenant) -> tuple[datetime | None, str]:
    """
    Retourne (date_expiration, type) pour la contrainte active du tenant.
    type = 'subscription' | 'trial' | ''
    Priorité : subscription_ends_at (plan payant) > trial_ends_at (essai).
    """
    sub_end = getattr(tenant, "subscription_ends_at", None)
    if sub_end and tenant.status in ("active", "paid"):
        if sub_end.tzinfo is None:
            sub_end = sub_end.replace(tzinfo=timezone.utc)
        return sub_end, "subscription"

    trial_end = tenant.trial_ends_at
    if trial_end and tenant.status in ("trial", "expired"):
        if trial_end.tzinfo is None:
            trial_end = trial_end.replace(tzinfo=timezone.utc)
        return trial_end, "trial"

    return None, ""


def plan_warning(tenant: Tenant) -> dict | None:
    """
    Retourne un dict de warning si le plan expire dans ≤ WARN_DAYS jours.
    Retourne None sinon (plan OK ou local).
    """
    if getattr(tenant, "is_local", False):
        return None

    expiry, kind = _effective_expiry(tenant)
    if not expiry:
        return None

    now = datetime.now(timezone.utc)
    delta = expiry - now
    days_left = delta.days  # négatif si déjà expiré

    if 0 <= days_left <= WARN_DAYS:
        label = "période d'essai" if kind == "trial" else "abonnement"
        return {
            "type":       kind,
            "days_left":  days_left,
            "expires_at": expiry.isoformat(),
            "message":    f"Votre {label} expire dans {days_left} jour(s). Renouvelez sur posconnect.ht",
        }
    return None


def _check_tenant_access(tenant: Tenant, db: Session, hard_block: bool = False) -> None:
    """
    Vérifie et applique les règles d'accès pour le tenant.
    hard_block=False → met à jour le statut mais ne bloque jamais (lecture / connexion)
    hard_block=True  → bloque avec 402 si expiré ou suspendu (ventes / commandes)
    """
    now = datetime.now(timezone.utc)

    expiry, kind = _effective_expiry(tenant)
    is_expired = expiry is not None and now > expiry
    past_grace  = is_expired and now > expiry + timedelta(days=GRACE_DAYS)

    # Auto-update statut — toujours, même sans hard_block
    if past_grace and tenant.status != "suspended":
        tenant.status = "suspended"
        db.commit()
    elif is_expired and not past_grace and kind == "trial" and tenant.status not in ("expired", "suspended"):
        tenant.status = "expired"
        db.commit()

    # Seules les routes d'écriture (ventes, commandes…) lèvent une exception
    if hard_block and (tenant.status in ("suspended", "expired") or is_expired):
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail=_SALES_BLOCKED_MSG,
        )


async def get_current_tenant(
    token: str | None = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> Tenant | None:
    """
    Retourne le Tenant pour les requêtes cloud (tenant_id dans le JWT).
    Retourne None pour les requêtes local-mode (pas de tenant_id).
    Ne bloque jamais la connexion/lecture — seul require_active_plan bloque les ventes.
    """
    if not token:
        return None

    payload = _decode_token(token)
    tenant_id: str | None = payload.get("tenant_id")
    if not tenant_id:
        return None

    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not tenant:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Tenant introuvable")

    _check_tenant_access(tenant, db, hard_block=False)
    return tenant


def require_tenant(tenant: Tenant | None = Depends(get_current_tenant)) -> Tenant:
    """Dépendance pour les routes cloud-only qui DOIVENT avoir un tenant."""
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Authentification cloud requise")
    return tenant


async def require_active_plan(
    token: str | None = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> None:
    """
    Dépendance à injecter sur les routes d'écriture (ventes, etc.).
    - No-op pour les utilisateurs locaux (pas de tenant_id dans le JWT).
    - Bloque avec 402 si le plan est expiré (même en période de grâce).
    """
    if not token:
        return  # local mode

    payload = _decode_token(token)
    tenant_id: str | None = payload.get("tenant_id")
    if not tenant_id:
        return  # local mode

    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not tenant:
        return

    _check_tenant_access(tenant, db, hard_block=True)
