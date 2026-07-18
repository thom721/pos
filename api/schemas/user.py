from pydantic import BaseModel,EmailStr
from typing import List, Optional
from uuid import UUID
from api.database import Base


class UserCreate(BaseModel):
    fname: str
    lname: str
    username: str
    phone: str
    address: Optional[str] = None
    password: str
    email: EmailStr
    is_active: bool = True
    roles: Optional[List[str]] = []
    permissions: Optional[List[str]] = []
    warehouse_id: Optional[List[str]] = None   # tableau de dépôts autorisés


class UserUpdate(BaseModel):
    id: str
    fname: str
    lname: str
    username: str
    phone: str
    address: Optional[str] = None
    password: str
    email: EmailStr
    is_active: bool = True
    roles: Optional[List[str]] = None
    permissions: Optional[List[str]] = None
    warehouse_id: Optional[List[str]] = None   # tableau de dépôts autorisés


class ChangePasswordRequest(BaseModel):
    new_password: str
    confirm_password: str


class UserRead(BaseModel):
    id: str
    fname: str
    lname: str
    username: str
    phone: Optional[str] = None
    address: Optional[str] = None
    password: str
    email: EmailStr
    is_active: bool = True
    roles: List[str] = []
    permissions: List[str] = []
    must_change_password: bool = True
    warehouse_id: Optional[List[str]] = None
    offline_hash: Optional[str] = None

    class Config:
        from_attributes = True

class UserPublicRead(BaseModel):
    """Utilisé par GET /api/users/ — sans offline_hash ni password."""
    id: str
    fname: str
    lname: str
    username: str
    phone: Optional[str] = None
    address: Optional[str] = None
    email: EmailStr
    is_active: bool = True
    roles: List[str] = []
    permissions: List[str] = []
    must_change_password: bool = True
    warehouse_id: Optional[List[str]] = None

    class Config:
        from_attributes = True


class UserSyncRead(BaseModel):
    """Utilisé par GET /api/users/offline-sync — inclut offline_hash pour la sync Android."""
    id: str
    fname: str
    lname: str
    username: str
    email: EmailStr
    is_active: bool = True
    roles: List[str] = []
    permissions: List[str] = []
    offline_hash: Optional[str] = None
    warehouse_id: Optional[List[str]] = None

    class Config:
        from_attributes = True


class UserOut(BaseModel):
    id: str
    username: str
    fname: str
    lname: str
    phone: Optional[str] = None
    address: Optional[str] = None
# orm_mode = True
