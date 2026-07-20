from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from api.database import get_db
from api.services.auth import Auth,Token,TokenData
from api.services.user_service import compute_offline_hash
from api.core.permissions import ROLE_PERMISSIONS
from datetime import timedelta
from typing import Annotated
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
import jwt


def _resolve_permissions(user) -> list[str]:
    """Compute effective permissions = current role perms + any extra explicit grants.

    Re-derives from ROLE_PERMISSIONS so that role changes take effect on next login
    without requiring individual user record updates.
    """
    roles = user.roles or []
    explicit = set(user.permissions or [])

    # Wildcard: admin stays admin
    if "all" in explicit or any(ROLE_PERMISSIONS.get(r, set()) == {"all"} for r in roles):
        return ["all"]

    role_perms: set[str] = set()
    for role in roles:
        role_perms.update(ROLE_PERMISSIONS.get(role, set()))

    # Keep only explicit permissions that are true custom grants (not role names)
    custom = {p for p in explicit if p not in roles and p != "all"}

    return sorted(role_perms | custom)



router = APIRouter(prefix='/api/auth',tags=["Token"])


ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 jours


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

    # Les utilisateurs ayant uniquement le rôle "serveur" n'accèdent pas à l'interface
    roles = set(user.roles or [])
    if roles and roles <= {'serveur'}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Ce compte est réservé au service en salle et n'a pas accès à l'interface.",
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
        'permissions': _resolve_permissions(user),
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
