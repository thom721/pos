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


class TransferInRequest(BaseModel):
    """Envoie du stock vers un entrepôt depuis un dépôt classique ou un autre
    entrepôt — voir entrepot_service.transfer_to_entrepot."""
    source_warehouse_id: str
    quantity: float
    reason: Optional[str] = None


class TransferReceipt(BaseModel):
    movement_id: str
    product_name: str
    quantity: float
    source_name: str
    source_address: Optional[str] = None
    target_name: str
    target_address: Optional[str] = None
    reason: Optional[str] = None
    created_at: datetime
