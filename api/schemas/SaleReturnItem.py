from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID


class SaleReturnItem(BaseModel):
    product_id: UUID
    quantity: float


class SaleReturnPayload(BaseModel):
    sale_id: UUID
    items: List[SaleReturnItem]
    refund_amount: float = 0
    reason: Optional[str] = None


class PurchaseReturnItem(BaseModel):
    product_id: UUID
    quantity: float


class PurchaseReturnPayload(BaseModel):
    purchase_id: UUID
    items: List[PurchaseReturnItem]
    reason: Optional[str] = None
