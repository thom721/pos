from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from api.database import get_db
from api.models.User import User
from api.services.auth import Auth
from api.core.config import settings
from api.core.permissions import has_permission
from jose import jwt, JWTError as InvalidTokenError


SECRET_KEY = settings.SECRET_KEY
ALGORITHM = settings.ALGORITHM

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")


async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except InvalidTokenError:
        raise credentials_exception

    auth = Auth(db)
    user = auth.get_user(username=username)
    if user is None:
        raise credentials_exception
    return user


def require_permission(permission: str):
    """
    Dependency factory — returns the current user if they hold the required
    permission (via direct permissions or their roles).  Raises 403 otherwise.

    Usage:
        current_user: User = Depends(require_permission(P.SALES_CREATE))
    """
    async def _check(current_user: User = Depends(get_current_user)) -> User:
        if not has_permission(
            current_user.permissions or [],
            current_user.roles or [],
            permission,
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Permission refusée: {permission}",
            )
        return current_user

    return _check
