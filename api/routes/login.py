from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from api.database import get_db
from api.services.auth_service import AuthService
from api.models.User import User
from api.schemas.login import LoginRequest, TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/login-user", response_model=TokenResponse)
def login(data: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email).first()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    auth = AuthService(db)
    if not auth.verify_password(data.password, user.password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    return {
        "access_token": auth.create_access_token(user.id),
        "refresh_token": auth.create_refresh_token(user.id),
        "token_type": "bearer"
    }


@router.post("/refresh", response_model=TokenResponse, include_in_schema=False)
def refresh(token: str, db: Session = Depends(get_db)):
    auth = AuthService(db)
    payload = auth.verify_token(token)

    if not payload:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    return {
        "access_token": auth.create_access_token(payload["sub"]),
        "refresh_token": token,
        "token_type": "bearer"
    }
