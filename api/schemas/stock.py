from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from api.schemas.product import ProductRead
from api.schemas.user import UserOut


class LowStockProductRead(BaseModel):
    id: str
    name: str
    stock: float
    alert_stock: int

class StockMovementRead(BaseModel):
    id: str
    type: str
    quantity: int
    source_type: Optional[str]
    source_id: Optional[str]
    note: Optional[str]
    created_at: datetime

    product: Optional[ProductRead]
    user: Optional[UserOut]

    class Config:
        from_attributes = True