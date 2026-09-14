"""Auth du programme de parrainage — indépendante de get_current_user/
get_current_tenant/require_superadmin (qui coexistent déjà tous les trois).
Le claim "type": "affiliate" est le discriminant qui empêche un token
tenant/user/superadmin d'être accepté ici, et inversement."""
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from sqlalchemy.orm import Session

from api.core.config import settings
from api.database import get_db
from api.models.Affiliate import Affiliate

_bearer = HTTPBearer(auto_error=False)


def create_affiliate_token(affiliate_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=30)
    payload = {"sub": affiliate_id, "type": "affiliate", "exp": expire}
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def get_current_affiliate(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> Affiliate:
    if not creds:
        raise HTTPException(status_code=401, detail="Connexion requise")
    try:
        payload = jwt.decode(creds.credentials, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Session expirée, reconnectez-vous")
    if payload.get("type") != "affiliate":
        raise HTTPException(status_code=401, detail="Token invalide")
    affiliate = db.query(Affiliate).filter(Affiliate.id == payload.get("sub")).first()
    if not affiliate or not affiliate.is_active:
        raise HTTPException(status_code=401, detail="Compte introuvable ou désactivé")
    return affiliate
