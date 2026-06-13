from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from api.database import get_db
from api.services.auth_service import AuthService

refresh_scheme = OAuth2PasswordBearer(tokenUrl="/refresh")


def get_current_user_from_refresh(
    token: str = Depends(refresh_scheme),
    db: Session = Depends(get_db)
):
    auth = AuthService(db)

    payload = auth.verify_token(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )

    return payload["sub"]
