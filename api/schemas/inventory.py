from pydantic import BaseModel
from typing import Optional, List
from uuid import UUID
from datetime import datetime


class InventoryItemInput(BaseModel):
    product_id: UUID
    counted_qty: float


class InventoryCreate(BaseModel):
    inventory_type: str = "full"          # 'full' | 'partial'
    category_ids: Optional[List[str]] = None
    notes: Optional[str] = None
    items: List[InventoryItemInput]


class InventoryPreviewItem(BaseModel):
    product_id: str
    product_name: str
    barcode: Optional[str] = None
    category: str
    category_id: str
    expected_qty: float


class InventoryRead(BaseModel):
    id: str
    reference: str
    inventory_type: str
    status: str
    notes: Optional[str] = None
    total_products: int
    discrepancy_count: int
    created_at: datetime

    class Config:
        from_attributes = True
