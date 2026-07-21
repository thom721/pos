from pydantic import BaseModel
from typing import List, Optional
from decimal import Decimal
from datetime import datetime


class ProformaItemInput(BaseModel):
    product_id: Optional[str] = None
    name: str
    quantity: float
    unit_price: float
    subtotal: float


class ProformaCreate(BaseModel):
    reference: str
    date: datetime
    client_id: Optional[str] = None
    client_name: Optional[str] = None
    discount: float = 0
    notes: Optional[str] = None
    currency: str = "HTG"
    status: str = "draft"
    warehouse_id: Optional[str] = None
    items: List[ProformaItemInput]


class ProformaUpdate(BaseModel):
    client_id: Optional[str] = None
    client_name: Optional[str] = None
    discount: Optional[float] = None
    notes: Optional[str] = None
    currency: Optional[str] = None
    status: Optional[str] = None
    warehouse_id: Optional[str] = None
    items: Optional[List[ProformaItemInput]] = None


class ProformaItemRead(BaseModel):
    id: str
    product_id: Optional[str] = None
    name: str
    quantity: Decimal
    unit_price: Decimal
    subtotal: Decimal

    class Config:
        from_attributes = True


class ProformaRead(BaseModel):
    id: str
    reference: str
    date: datetime
    client_id: Optional[str] = None
    client_name: Optional[str] = None
    discount: Decimal
    notes: Optional[str] = None
    currency: str
    status: str
    warehouse_id: Optional[str] = None
    created_at: datetime
    items: List[ProformaItemRead] = []

    class Config:
        from_attributes = True
