from pydantic import BaseModel, EmailStr
from typing import Optional


class CustomerBase(BaseModel):
    name: str
    fname: Optional[str] = ''
    nif: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    credit_limit: Optional[float] = 0


class CustomerCreate(CustomerBase):
    pass


class CustomerRead(CustomerBase):
    id: str
    credit_limit: float = 0
    # Lecture seule — géré uniquement par sale_service (jamais accepté en
    # entrée sur CustomerCreate/CustomerUpdate).
    loyalty_balance: float = 0
    full_name: str = ''

    model_config = {"from_attributes": True}


class CustomerUpdate(BaseModel):
    name: Optional[str] = None
    fname: Optional[str] = None
    nif: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    credit_limit: Optional[float] = None
