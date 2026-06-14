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

GRACE_DAYS = 10  # days after expiry before hard block

_SUSPENDED_MSG = (
    "Votre abonnement est suspendu ou expiré. "
    "Veuillez renouveler votre abonnement sur posconnect.ht"
)
_GRACE_MSG = (
    "Votre période d'essai est terminée. "
    "Vous disposez d'une période de grâce de 10 jours pour renouveler."
)


def _decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        return {}


async def get_current_tenant(
    token: str | None = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> Tenant | None:
    """
    Returns the Tenant for cloud requests (tenant_id in JWT).
    Returns None for local-mode requests (no tenant_id in JWT).
    Raises 403 if the tenant is suspended/expired.
    """
    if not token:
        return None

    payload = _decode_token(token)
    tenant_id: str | None = payload.get("tenant_id")

    if not tenant_id:
        return None  # local mode — no tenant isolation

    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not tenant:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Tenant introuvable")

    if tenant.status == "suspended":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail=_SUSPENDED_MSG)

    if tenant.status in ("trial", "expired") and tenant.trial_ends_at:
        trial_end = tenant.trial_ends_at
        if trial_end.tzinfo is None:
            trial_end = trial_end.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        if now > trial_end:
            grace_end = trial_end + timedelta(days=GRACE_DAYS)
            if now > grace_end:
                # Hard block after grace period
                tenant.status = "suspended"
                db.commit()
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                    detail=_SUSPENDED_MSG)
            else:
                # Grace period — let through but mark tenant
                if tenant.status != "expired":
                    tenant.status = "expired"
                    db.commit()

    return tenant


def require_tenant(tenant: Tenant | None = Depends(get_current_tenant)) -> Tenant:
    """Use this dependency on cloud-only routes that MUST have a tenant."""
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Authentification cloud requise")
    return tenant
