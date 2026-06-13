from pydantic import BaseModel
from typing import List, Optional
from decimal import Decimal
from datetime import datetime


class InvoiceItemInput(BaseModel):
    product_id: Optional[str] = None
    name: str
    quantity: float
    unit_price: float
    subtotal: float


class InvoiceCreate(BaseModel):
    reference: str
    date: datetime
    due_date: Optional[datetime] = None
    client_id: Optional[str] = None
    client_name: Optional[str] = None
    discount: float = 0
    notes: Optional[str] = None
    currency: str = "HTG"
    status: str = "draft"
    items: List[InvoiceItemInput]


class InvoiceUpdate(BaseModel):
    due_date: Optional[datetime] = None
    client_id: Optional[str] = None
    client_name: Optional[str] = None
    discount: Optional[float] = None
    notes: Optional[str] = None
    currency: Optional[str] = None
    status: Optional[str] = None
    items: Optional[List[InvoiceItemInput]] = None


class InvoicePaymentInput(BaseModel):
    amount: float


class InvoiceItemRead(BaseModel):
    id: str
    product_id: Optional[str] = None
    name: str
    quantity: Decimal
    unit_price: Decimal
    subtotal: Decimal

    class Config:
        from_attributes = True


class InvoiceRead(BaseModel):
    id: str
    reference: str
    date: datetime
    due_date: Optional[datetime] = None
    client_id: Optional[str] = None
    client_name: Optional[str] = None
    discount: Decimal
    paid_amount: Decimal
    notes: Optional[str] = None
    currency: str
    status: str
    created_at: datetime
    items: List[InvoiceItemRead] = []

    class Config:
        from_attributes = True
