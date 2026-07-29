from datetime import time
from pydantic import BaseModel, field_validator
from typing import Optional


class DiscountCreate(BaseModel):
    name: str
    type: str            # "percentage" | "fixed"
    value: float
    scope: str = "both"  # "receipt" | "item" | "both"
    is_automatic: bool = False
    is_active: bool = True
    schedule_days: Optional[str] = None   # "0,1,2,3,4" (0=lundi)
    schedule_start: Optional[time] = None
    schedule_end: Optional[time] = None
    min_quantity: Optional[float] = None  # seuil de quantité (rabais article)
    product_ids: Optional[list[str]] = None  # produits liés — suggestion auto en caisse


class DiscountRead(BaseModel):
    id: str
    name: str
    type: str
    value: float
    scope: str
    is_automatic: bool
    is_active: bool
    schedule_days: Optional[str] = None
    schedule_start: Optional[time] = None
    schedule_end: Optional[time] = None
    min_quantity: Optional[float] = None
    product_ids: Optional[list[str]] = None

    @field_validator("type", "scope", mode="before")
    @classmethod
    def _enum_to_value(cls, v):
        return v.value if hasattr(v, "value") else v

    class Config:
        from_attributes = True


class DiscountUpdate(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    value: Optional[float] = None
    scope: Optional[str] = None
    is_automatic: Optional[bool] = None
    is_active: Optional[bool] = None
    schedule_days: Optional[str] = None
    schedule_start: Optional[time] = None
    schedule_end: Optional[time] = None
    min_quantity: Optional[float] = None
    product_ids: Optional[list[str]] = None
