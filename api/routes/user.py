from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from api.services.user_service import UserService
from api.schemas.user import UserCreate, UserRead, UserUpdate, ChangePasswordRequest
from api.database import get_db
from api.dependencies.auth import require_permission, get_current_user
from api.core.permissions import P
from api.models.User import User

router = APIRouter(tags=['Users'])


@router.post("/users", response_model=UserRead)
def create_user(
    data: UserCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.USERS_CREATE)),
):
    try:
        return UserService(db).create(data)
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/users/", response_model=List[UserRead])
def list_users(
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.USERS_READ)),
):
    return UserService(db).list()


@router.get("/users/{user_id}", response_model=UserRead)
def get_user(
    user_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.USERS_READ)),
):
    user = UserService(db).get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.put("/users/{user_id}", response_model=UserRead)
def update_user(
    user_id: str,
    data: UserUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.USERS_UPDATE)),
):
    user = UserService(db).update(user_id, data)
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
    UserService(db).change_password(current_user.id, data.new_password)
    return {"ok": True}


@router.delete("/users/{user_id}", response_model=dict)
def delete_user(
    user_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.USERS_DELETE)),
):
    success = UserService(db).delete(user_id)
    if not success:
        raise HTTPException(status_code=404, detail="User not found")
    return {"ok": True}
