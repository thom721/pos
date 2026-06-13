from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from api.schemas.product import ProductRead
from api.schemas.user import UserOut

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