from pydantic import BaseModel
from typing import Optional, List


class EntrepotCreate(BaseModel):
    name: str = "Entrepôt"


class StockAdjustRequest(BaseModel):
    quantity: float
    reason: Optional[str] = None


class DistributeAllocation(BaseModel):
    warehouse_id: str
    quantity: float


class DistributeRequest(BaseModel):
    allocations: List[DistributeAllocation]
