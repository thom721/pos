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

    # Avertissement plan expirant (cloud seulement)
    warning = None
    if user.tenant_id:
        from api.models.Tenant import Tenant as TenantModel
        from api.core.tenant import plan_warning
        from api.utils.email import maybe_send_warning
        tenant = db.query(TenantModel).filter(TenantModel.id == user.tenant_id).first()
        if tenant and not getattr(tenant, "is_local", False):
            warning = plan_warning(tenant)
            # Email uniquement au propriétaire du tenant
            if warning and user.email == tenant.owner_email:
                maybe_send_warning(tenant, db)

    return {
        "access_token": auth.create_access_token(user.id),
        "refresh_token": auth.create_refresh_token(user.id),
        "token_type": "bearer",
        "plan_warning": warning,
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
