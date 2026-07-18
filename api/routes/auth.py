from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from api.database import get_db
from api.services.auth import Auth,Token,TokenData
from api.services.user_service import compute_offline_hash
from datetime import timedelta
from typing import Annotated
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
import jwt



router = APIRouter(prefix='/api/auth',tags=["Token"])


ACCESS_TOKEN_EXPIRE_MINUTES = 30


@router.post("/login")
def login_for_access_token(
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],db: Session = Depends(get_db)
) -> Token:
    auth = Auth(db)
    user = auth.authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Mise à jour du hash offline pour les utilisateurs existants
    if not user.offline_hash and user.email:
        user.offline_hash = compute_offline_hash(user.email, form_data.password)
        db.commit()

    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )

    # Avertissement plan expirant (cloud seulement)
    warning = None
    if user.tenant_id:
        from api.models.Tenant import Tenant
        from api.core.tenant import plan_warning
        from api.utils.email import maybe_send_warning
        tenant = db.query(Tenant).filter(Tenant.id == user.tenant_id).first()
        if tenant and not getattr(tenant, "is_local", False):
            warning = plan_warning(tenant)
            # Email uniquement au propriétaire du tenant
            if warning and user.email == tenant.owner_email:
                maybe_send_warning(tenant, db)

    return Token(access_token=access_token, token_type="bearer", user={
        'id': user.id,
        'username': user.username,
        'fname': user.fname,
        'lname': user.lname,
        'email': user.email,
        'phone': user.phone,
        'address': user.address,
        'roles': user.roles,
        'permissions': user.permissions,
        'must_change_password': user.must_change_password,
    }, plan_warning=warning)


# @router.get("/users/me/", response_model=User)
# async def read_users_me(
#     current_user: Annotated[User, Depends(auth.get_current_active_user)],
# ):
#     return current_user


# @router.get("/users/me/items/")
# async def read_own_items(
#     current_user: Annotated[User, Depends(auth.get_current_active_user)],
# ):
#     return [{"item_id": "Foo", "owner": current_user.username}]

# async def get_current_user(token: Annotated[str, Depends(oauth2_scheme)],db: Session = Depends(get_db)):
#     auth = Auth(db)
#     credentials_exception = HTTPException(
#         status_code=status.HTTP_401_UNAUTHORIZED,
#         detail="Could not validate credentials",
#         headers={"WWW-Authenticate": "Bearer"},
#     )
#     try:
#         payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
#         username = payload.get("sub")
#         if username is None:
#             raise credentials_exception
#         token_data = TokenData(username=username)
#     except InvalidTokenError:
#         raise credentials_exception
#     user = auth.get_user(username=token_data.username)
#     if user is None:
#         raise credentials_exception
#     return user
