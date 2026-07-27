import hashlib
from typing import List, Optional
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from api.models.User import User  # SQLAlchemy
from api.services.auth_service import AuthService
from fastapi import HTTPException
from api.services.auth import get_password_hash
from api.services.base_service import TenantService

from api.schemas.user import UserCreate, UserUpdate, UserRead  # Pydantic


def compute_offline_hash(email: str, password: str) -> str:
    return hashlib.sha256(f"{email.lower()}:{password}".encode()).hexdigest()

class UserService(TenantService):
    def __init__(self, db: Session, tenant_id: str | None = None):
        super().__init__(db, tenant_id)
        self.auth = AuthService(db)

    def _check_unique(self, username: str, email: str | None, exclude_id: str | None = None) -> None:
        q_user = self._q(User).filter(User.username == username)
        if exclude_id:
            q_user = q_user.filter(User.id != exclude_id)
        if q_user.first():
            raise HTTPException(status_code=409, detail=f"Le nom d'utilisateur '{username}' est déjà pris.")
        if email:
            q_email = self.db.query(User).filter(User.email == email)
            if exclude_id:
                q_email = q_email.filter(User.id != exclude_id)
            if q_email.first():
                raise HTTPException(status_code=409, detail=f"L'adresse email '{email}' est déjà utilisée.")

    def create(self, data: UserCreate) -> User:
        self._check_unique(data.username, data.email or None)
        try:
            user = User(
                fname=data.fname,
                lname=data.lname,
                username=data.username,
                phone=data.phone,
                address=data.address,
                email=data.email or None,
                password=get_password_hash(data.password),
                offline_hash=compute_offline_hash(data.email, data.password) if data.email else None,
                roles=data.roles or [],
                permissions=data.permissions or [],
                must_change_password=True,
                warehouse_id=data.warehouse_id,
            )
            self._set_tenant(user)
            self.db.add(user)
            self.db.commit()
            self.db.refresh(user)
            return user
        except IntegrityError as e:
            self.db.rollback()
            err = str(e.orig).lower() if e.orig else ''
            if 'email' in err:
                raise HTTPException(status_code=409, detail=f"L'adresse email '{data.email}' est déjà utilisée.")
            raise HTTPException(status_code=409, detail=f"Le nom d'utilisateur '{data.username}' est déjà pris.")

    def change_password(self, user_id: str, new_password: str) -> User:
        user = self.get(user_id)
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur introuvable")
        user.password = get_password_hash(new_password)
        if user.email:
            user.offline_hash = compute_offline_hash(user.email, new_password)
        user.must_change_password = False
        self.db.commit()
        self.db.refresh(user)
        return user

    def get(self, user_id: str) -> Optional[User]:
        return self._q(User).filter(User.id == user_id).first()

    def list(self) -> List[User]:
        return self._q(User).all()

    def update(self, user_id: str, data: UserUpdate) -> Optional[User]:
        user = self.get(user_id)
        if not user:
            return None
        new_username = data.dict(exclude_unset=True).get('username', user.username)
        new_email = data.dict(exclude_unset=True).get('email', user.email)
        self._check_unique(new_username, new_email, exclude_id=user_id)
        new_password = None
        for field, value in data.dict(exclude_unset=True).items():
            if field == 'password':
                if value:
                    user.password = get_password_hash(value)
                    user.must_change_password = True
                    new_password = value
            else:
                setattr(user, field, value)
        if new_password and user.email:
            user.offline_hash = compute_offline_hash(user.email, new_password)
        try:
            self.db.commit()
            self.db.refresh(user)
            return user
        except IntegrityError as e:
            self.db.rollback()
            err = str(e.orig).lower() if e.orig else ''
            if 'email' in err:
                raise HTTPException(status_code=409, detail=f"L'adresse email '{new_email}' est déjà utilisée.")
            raise HTTPException(status_code=409, detail=f"Le nom d'utilisateur '{new_username}' est déjà pris.")

    def delete(self, user_id: str) -> bool:
        user = self.get(user_id)
        if not user:
            return False
        try:
            self.db.delete(user)
            self.db.commit()
            return True
        except IntegrityError:
            self.db.rollback()
            raise HTTPException(
                status_code=409,
                detail="Impossible de supprimer : cet utilisateur a des ventes, sessions "
                       "ou autres données associées. Désactivez-le plutôt.",
            )
