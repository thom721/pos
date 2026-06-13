from pydantic import BaseModel,EmailStr
from typing import List, Optional
from uuid import UUID 


# 🔹 Customer
# class Customer(BaseModel):
#     name: str
#     email: Optional[EmailStr] = None
#     phone: Optional[str] = None
#     address: Optional[str] = None
#     user_id: Optional[UUID] = None

# ===== Customer Schemas =====
class CustomerBase(BaseModel):
    name: str
    email: Optional[EmailStr]
    phone: Optional[str]
    address: Optional[str]

class CustomerCreate(CustomerBase):
    pass

class CustomerRead(CustomerBase):
    id: str

    model_config = {
        "from_attributes": True
    }

class CustomerUpdate(BaseModel):
    name: Optional[str]
    email: Optional[EmailStr]
    phone: Optional[str]
    address: Optional[str]