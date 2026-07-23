from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
from decimal import Decimal
from datetime import datetime, date
from api.schemas.user import UserRead

class ReceiptItemCreate(BaseModel):
    purchase_item_id: str
    purchase_receipt_id: str
    product_id: str
    received_qty: float
    lot_number: str | None = None
    expiry_date: date | None = None

class PurchaseReceiptCreate(BaseModel):
    purchase_id: str
    received_by: str | None = None
    note: str | None = None
    warehouse_id: str | None = None
    items: list[ReceiptItemCreate]

# class PurchaseCreate(BaseModel):
#     supplier_id: UUID
#     paid_amount: float = 0
#     items: List[PurchaseItemInput]


class SupplierRead(BaseModel):
    id: str
    name: str

    class Config:
        from_attributes = True


    class Config:
        from_attributes = True


class ProductRead(BaseModel):
    id: str
    name: str

    class Config:
        from_attributes = True


class PurchaseItemRead(BaseModel):
    id: str
    ordered_qty: int
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
    items: List[PurchaseItemRead]
    payments: List[PaymentRead]

    class Config:
        from_attributes = True
