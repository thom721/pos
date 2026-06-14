from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from api.core.config import settings

_bearer = HTTPBearer(auto_error=False)


def require_superadmin(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
):
    if not creds:
        raise HTTPException(status_code=401, detail="Token superadmin requis")
    try:
        payload = jwt.decode(
            creds.credentials, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        if payload.get("role") != "superadmin":
            raise HTTPException(status_code=403, detail="Accès réservé aux superadmins")
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Token invalide ou expiré")
