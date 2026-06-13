from pydantic import BaseModel,EmailStr
from typing import List, Optional
from uuid import UUID
# 🔹 Supplier
from pydantic import BaseModel, EmailStr
from typing import Optional

# ===== Supplier Schemas =====
class SupplierBase(BaseModel):
    name: str
    email: Optional[EmailStr]
    phone: Optional[str]
    address: Optional[str]

class SupplierCreate(SupplierBase):
    pass

class SupplierRead(SupplierBase):
    id: str

    model_config = {
        "from_attributes": True
    }

class SupplierUpdate(BaseModel):
    name: Optional[str]
    email: Optional[EmailStr]
    phone: Optional[str]
    address: Optional[str]








