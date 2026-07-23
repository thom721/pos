from pydantic import BaseModel, field_serializer
from typing import List, Optional
from uuid import UUID
from decimal import Decimal
from datetime import datetime, timezone, timedelta
from .category import CategoryRead

_HAITI = timezone(timedelta(hours=-5))


class SaleItemInput(BaseModel):
    product_id: UUID
    quantity: float
    unit_price: float
    subtotal: float


class SaleCreate(BaseModel):
    client_id: Optional[str] = None      # UUID généré côté client pour l'offline-first
    customer_id: Optional[UUID] = None
    warehouse_id: Optional[str] = None
    discount: float = 0
    paid_amount: float = 0
    total_amount: float = 0
    payment_method: Optional[str] = None
    approval_code: Optional[str] = None
    items: List[SaleItemInput]


class SaleUpdate(BaseModel):
    customer_id: Optional[UUID] = None
    discount: float = 0
    payment_method: Optional[str] = "CASH"
    additional_payment: float = 0  # paiement supplémentaire collecté maintenant
    items: List[SaleItemInput]


class CustomerRead(BaseModel):
    id: str
    name: str
    phone: str

    class Config:
        from_attributes = True


class UserRead(BaseModel):
    id: str
    fname: str
    lname: str

    class Config:
        from_attributes = True


class ProductRead(BaseModel):
    id: str
    name: str

    class Config:
        from_attributes = True


class SaleItemRead(BaseModel):
    id: str
    product_id: Optional[str] = None
    label: Optional[str] = None
    quantity: float
    unit_price: Decimal
    original_price: Optional[Decimal] = None
    subtotal: Decimal
    product: Optional[ProductRead] = None
    returned_qty: float = 0

    class Config:
        from_attributes = True


class PaymentRead(BaseModel):
    id: str
    amount: Decimal
    method: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class SaleRead(BaseModel):
    id: str
    reference: str
    total_amount: Decimal
    discount: Decimal
    final_amount: Decimal
    paid_amount: Decimal
    status: str
    created_at: datetime

    customer: Optional[CustomerRead] = None
    user: Optional[UserRead] = None
    items: Optional[List[SaleItemRead]] = None
    payments: Optional[List[PaymentRead]] = None

    created_at_str: str | None = None

    @field_serializer("created_at_str")
    def serialize_created_at_str(self, _):
        haiti_dt = self.created_at.astimezone(_HAITI)
        return haiti_dt.strftime("%d/%m/%Y à %H:%M")

    class Config:
        from_attributes = True


class ProductSaleItem(BaseModel):
    id: str
    name: str
    barcode: str | None
    sale_price: float
    alert_stock: int
    image_url: str | None = None
    stock: float | None = None
    category: CategoryRead

    class Config:
        from_attributes = True
