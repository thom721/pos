from typing import List, Optional
from uuid import UUID, uuid4 
from pydantic import BaseModel, EmailStr, Field
from datetime import datetime, timezone 
  




# 🔹 Base avec UUID et timestamps
class BaseUUIDModel(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    created_at: datetime = Field(default_factory=datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=datetime.now(timezone.utc))


# 🔹 User
class User(BaseUUIDModel):
    name: str
    email: EmailStr
    is_active: bool = True


# 🔹 Supplier
class Supplier(BaseUUIDModel):
    name: str
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    address: Optional[str] = None


# 🔹 Product
class Product(BaseUUIDModel):
    name: str
    price: float = 0.0
    stock: int = 0
    owner_id: Optional[UUID] = None
    supplier_id: Optional[UUID] = None


# 🔹 Customer
class Customer(BaseUUIDModel):
    name: str
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    user_id: Optional[UUID] = None


# 🔹 Service
class Service(BaseUUIDModel):
    name: str
    price: float = 0.0
    description: Optional[str] = None
    user_id: Optional[UUID] = None
    supplier_id: Optional[UUID] = None
    customer_id: Optional[UUID] = None


# 🔹 Exemple pour réponse avec relations
class UserWithProducts(User):
    products: List[Product] = []

class CustomerWithServices(Customer):
    services: List[Service] = []
