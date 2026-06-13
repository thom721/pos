from pydantic import BaseModel
from typing import Optional
from decimal import Decimal
from datetime import datetime


class PaymentUserInfo(BaseModel):
    fname: str
    lname: str

    class Config:
        from_attributes = True


class PaymentCreate(BaseModel):
    reference_type: str  # SALE ou PURCHASE
    reference_id: str
    amount: float
    method: str  # CASH, BANK, MOBILE


class PaymentResponse(BaseModel):
    id: str
    reference_type: str
    reference_id: str
    amount: Decimal
    method: str
    created_at: datetime
    user: Optional[PaymentUserInfo] = None

    class Config:
        from_attributes = True
