from typing import List, Optional
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from api.models.User import User  # SQLAlchemy
from api.services.auth_service import AuthService
from fastapi import HTTPException
from api.services.auth import get_password_hash
from api.services.base_service import TenantService

from api.schemas.user import UserCreate, UserUpdate, UserRead  # Pydantic

class UserService(TenantService):
    def __init__(self, db: Session, tenant_id: str | None = None):
        super().__init__(db, tenant_id)
        self.auth = AuthService(db)

    def create(self, data: UserCreate) -> User:
        existing = self._q(User).filter(User.username == data.username).first()
        if existing:
            raise HTTPException(status_code=400, detail=f"Le nom d'utilisateur '{data.username}' est déjà pris.")
        try:
            user = User(
                fname=data.fname,
                lname=data.lname,
                username=data.username,
                phone=data.phone,
                address=data.address,
                email=data.email,
                password=get_password_hash(data.password),
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
        except IntegrityError:
            self.db.rollback()
            raise HTTPException(status_code=400, detail=f"Le nom d'utilisateur '{data.username}' est déjà pris.")
        except Exception as e:
            self.db.rollback()
            raise HTTPException(status_code=500, detail=str(e))

    def change_password(self, user_id: str, new_password: str) -> User:
        user = self.get(user_id)
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur introuvable")
        user.password = get_password_hash(new_password)
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
        for field, value in data.dict(exclude_unset=True).items():
            if field == 'password' and value:
                setattr(user, field, get_password_hash(value))
            else:
                setattr(user, field, value)
        self.db.commit()
        self.db.refresh(user)
        return user

    def delete(self, user_id: str) -> bool:
        user = self.get(user_id)
        if not user:
            return False
        self.db.delete(user)
        self.db.commit()
        return True
