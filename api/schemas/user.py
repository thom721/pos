from pydantic import BaseModel,EmailStr
from typing import List, Optional
from uuid import UUID
from api.database import Base


class UserCreate(BaseModel):
    fname: str
    lname: str
    username: str
    phone: str
    address: str
    password: str
    email: EmailStr
    is_active: bool = True
    roles: Optional[List[str]] = []
    permissions: Optional[List[str]] = []


class UserUpdate(BaseModel):
    id: str
    fname: str
    lname: str
    username: str
    phone: str
    address: str
    password: str
    email: EmailStr
    is_active: bool = True
    roles: Optional[List[str]] = None
    permissions: Optional[List[str]] = None


class ChangePasswordRequest(BaseModel):
    new_password: str
    confirm_password: str


class UserRead(BaseModel):
    id: str
    fname: str
    lname: str
    username: str
    phone: str
    address: str
    password: str
    email: EmailStr
    is_active: bool = True
    roles: List[str] = []
    permissions: List[str] = []
    must_change_password: bool = True

class UserOut(BaseModel):
    id: str
    username: str
    fname: str
    lname: str 
    phone: str
    address: str
# orm_mode = True
 