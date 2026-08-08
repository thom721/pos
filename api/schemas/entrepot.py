from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class EntrepotCreate(BaseModel):
    name: str = "Entrepôt"
    address: Optional[str] = None


class EntrepotRead(BaseModel):
    id: str
    name: str
    address: Optional[str] = None
    is_active: bool
    subscription_ends_at: Optional[datetime] = None
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class StockAdjustRequest(BaseModel):
    quantity: float
    reason: Optional[str] = None


class DistributeAllocation(BaseModel):
    warehouse_id: str
    quantity: float


class DistributeRequest(BaseModel):
    allocations: List[DistributeAllocation]
