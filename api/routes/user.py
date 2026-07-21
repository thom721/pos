from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from api.services.user_service import UserService
from api.schemas.user import UserCreate, UserRead, UserPublicRead, UserSyncRead, UserUpdate, ChangePasswordRequest
from api.database import get_db
from api.dependencies.auth import require_permission, get_current_user
from api.core.permissions import P, ROLE_PERMISSIONS
from api.models.User import User


def _resolve_permissions(user) -> list[str]:
    roles = user.roles or []
    explicit = set(user.permissions or [])
    if "all" in explicit or any(ROLE_PERMISSIONS.get(r, set()) == {"all"} for r in roles):
        return ["all"]
    role_perms: set[str] = set()
    for role in roles:
        role_perms.update(ROLE_PERMISSIONS.get(role, set()))
    custom = {p for p in explicit if p not in roles and p != "all"}
    return sorted(role_perms | custom)

router = APIRouter(tags=['Users'])


@router.post("/users", response_model=UserRead)
def create_user(
    data: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.USERS_CREATE)),
):
    try:
        return UserService(db, tenant_id=current_user.tenant_id).create(data)
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/users/", response_model=List[UserPublicRead])
def list_users(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.USERS_READ)),
):
    return UserService(db, tenant_id=current_user.tenant_id).list()


@router.get("/users/offline-sync")
def list_users_offline_sync(
    warehouse_id: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Retourne les utilisateurs du tenant pour l'auth hors ligne.

    Si warehouse_id est fourni, retourne seulement les utilisateurs rattachés
    à ce dépôt + les utilisateurs à accès total (warehouse_id vide = admin).
    """
    users = UserService(db, tenant_id=current_user.tenant_id).list()
    if warehouse_id:
        def _wh_list(raw) -> list:
            import json as _j
            if not raw:
                return []
            if isinstance(raw, list):
                return raw
            if isinstance(raw, str) and raw.strip().startswith('['):
                try:
                    return _j.loads(raw)
                except Exception:
                    pass
            return [raw]
        users = [
            u for u in users
            if not _wh_list(u.warehouse_id) or warehouse_id in _wh_list(u.warehouse_id)
        ]
    return [
        {
            "id": u.id,
            "fname": u.fname,
            "lname": u.lname,
            "username": u.username,
            "email": u.email,
            "is_active": u.is_active,
            "roles": u.roles or [],
            "permissions": _resolve_permissions(u),
            "offline_hash": u.offline_hash,
            "warehouse_id": u.warehouse_id,
        }
        for u in users
    ]


@router.get("/users/{user_id}", response_model=UserRead)
def get_user(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.USERS_READ)),
):
    user = UserService(db, tenant_id=current_user.tenant_id).get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.put("/users/{user_id}", response_model=UserRead)
def update_user(
    user_id: str,
    data: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.USERS_UPDATE)),
):
    user = UserService(db, tenant_id=current_user.tenant_id).update(user_id, data)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.post("/users/me/change-password", response_model=dict)
def change_my_password(
    data: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if data.new_password != data.confirm_password:
        raise HTTPException(status_code=400, detail="Les mots de passe ne correspondent pas")
    if len(data.new_password) < 6:
        raise HTTPException(status_code=400, detail="Le mot de passe doit contenir au moins 6 caractères")
    UserService(db, tenant_id=current_user.tenant_id).change_password(current_user.id, data.new_password)
    return {"ok": True}


@router.delete("/users/{user_id}", response_model=dict)
def delete_user(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.USERS_DELETE)),
):
    success = UserService(db, tenant_id=current_user.tenant_id).delete(user_id)
    if not success:
        raise HTTPException(status_code=404, detail="User not found")
    return {"ok": True}
