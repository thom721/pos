from pydantic import BaseModel
from typing import Optional
from decimal import Decimal
from datetime import datetime


class DebtRead(BaseModel):
    id: str
    reference_type: str
    reference_id: str
    partner_type: str
    partner_id: str
    total_amount: Decimal
    paid_amount: Decimal
    balance: Decimal
    status: str
    created_at: datetime
    partner_name: Optional[str] = None

    class Config:
        from_attributes = True
