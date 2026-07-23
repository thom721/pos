from pydantic import BaseModel,field_serializer
from typing import List, Optional
from uuid import UUID  
from decimal import Decimal
from datetime import datetime
from api.schemas.user import UserRead

class PurchaseItemInput(BaseModel):
    product_id: UUID
    ordered_qty: float
    remaining_qty:float
    unit_price: float

class PurchaseCreate(BaseModel):
    supplier_id: Optional[UUID] = None
    paid_amount: float = 0
    total_amount: float = 0
    warehouse_id: Optional[str] = None
    items: List[PurchaseItemInput]




class SupplierRead(BaseModel):
    id: str
    name: str

    class Config:
        from_attributes = True



class ProductRead(BaseModel):
    id: str
    name: str

    class Config:
        from_attributes = True


class PurchaseItemRead(BaseModel):
    id: str
    ordered_qty: float
    remaining_qty: Optional[float]=None
    unit_price: Decimal
    subtotal: Decimal
    product: ProductRead

    class Config:
        from_attributes = True


class PaymentRead(BaseModel):
    id: str
    amount: Decimal
    method: str
    created_at: datetime

    class Config:
        from_attributes = True

class PurchaseRead(BaseModel):
    id: str
    reference: str
    total_amount: Decimal
    paid_amount: Decimal
    status: str
    created_at: datetime
    warehouse_id: Optional[str] = None

    supplier: Optional[SupplierRead]
    user: Optional[UserRead]
    items: Optional[List[PurchaseItemRead]]
    payments: Optional[List[PaymentRead]]

    created_at_str: str | None = None

    @field_serializer("created_at_str")
    def serialize_created_at_str(self, _):
        return self.created_at.strftime("%d/%m/%Y à %H:%M")

    # @field_serializer("created_at")
    # def serialize_created_at(self, created_at: datetime):
    #     return created_at.strftime("%Y-%m-%d %H:%M")

    class Config:
        from_attributes = True
