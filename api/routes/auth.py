from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
from api.database import get_db
from api.services.auth import Auth,Token,TokenData,get_password_hash
from api.services.user_service import compute_offline_hash
from api.core.permissions import ROLE_PERMISSIONS
from api.core.dt_coerce import now_local
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
        data={"sub": user.username, "perm_v": user.permissions_version or 0},
        expires_delta=access_token_expires,
    )

    # Avertissement plan expirant (cloud seulement) — affiché en app ici ;
    # l'email correspondant part une fois par jour le matin, pas à chaque
    # connexion (voir _daily_notif_loop dans api/main.py).
    warning = None
    if user.tenant_id:
        from api.models.Tenant import Tenant
        from api.core.tenant import plan_warning
        tenant = db.query(Tenant).filter(Tenant.id == user.tenant_id).first()
        if tenant and not getattr(tenant, "is_local", False):
            warning = plan_warning(tenant)

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


# ── Réinitialisation de mot de passe ────────────────────────────────────────

class ForgotPasswordRequest(BaseModel):
    email: str


class ResetPasswordRequest(BaseModel):
    email: str
    code: str
    new_password: str


_GENERIC_FORGOT_MESSAGE = (
    "Si un compte existe avec cet email, un code de vérification vient d'être envoyé."
)


@router.post("/forgot-password")
def forgot_password(body: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """Génère un code à 6 chiffres (expire 15 min) et l'envoie par email.
    Répond toujours le même message générique, que l'email existe ou non —
    évite qu'un attaquant puisse énumérer les comptes existants."""
    import random
    from api.models.User import User
    from api.models.PlatformConfig import PlatformConfig
    from api.utils.email import send_password_reset_email

    email = body.email.strip().lower()
    user = db.query(User).filter(User.email.ilike(email), User.is_active == True).first()  # noqa: E712
    if user:
        code = f"{random.randint(0, 999999):06d}"
        user.password_reset_code = code
        user.password_reset_expires_at = now_local() + timedelta(minutes=15)
        db.commit()

        cfg = db.query(PlatformConfig).first()
        if cfg and cfg.smtp_host and cfg.smtp_from:
            send_password_reset_email(
                to_addr=user.email,
                code=code,
                smtp_host=cfg.smtp_host,
                smtp_port=cfg.smtp_port,
                smtp_user=cfg.smtp_user,
                smtp_password=cfg.smtp_password,
                smtp_from=cfg.smtp_from,
            )

    return {"message": _GENERIC_FORGOT_MESSAGE}


@router.post("/reset-password")
def reset_password(body: ResetPasswordRequest, db: Session = Depends(get_db)):
    from api.models.User import User

    email = body.email.strip().lower()
    user = db.query(User).filter(User.email.ilike(email), User.is_active == True).first()  # noqa: E712
    if (
        not user
        or not user.password_reset_code
        or not user.password_reset_expires_at
        or user.password_reset_code != body.code.strip()
        or user.password_reset_expires_at < now_local()
    ):
        raise HTTPException(status_code=400, detail="Code invalide ou expiré")

    if len(body.new_password) < 6:
        raise HTTPException(status_code=400, detail="Le mot de passe doit contenir au moins 6 caractères")

    user.password = get_password_hash(body.new_password)
    # offline_hash est dérivé de (email, password) — sans le recalculer ici,
    # la connexion hors-ligne resterait cassée après un reset (voir login,
    # qui ne le recalcule que s'il est absent, pas s'il est simplement périmé).
    if user.email:
        user.offline_hash = compute_offline_hash(user.email, body.new_password)
    user.password_reset_code = None
    user.password_reset_expires_at = None
    user.must_change_password = False
    db.commit()

    return {"message": "Mot de passe réinitialisé avec succès."}


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
