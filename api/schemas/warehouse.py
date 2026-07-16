from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class WarehouseCreate(BaseModel):
    name: str
    description: Optional[str] = None


class WarehouseUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    is_active: Optional[bool] = None


class WarehouseRead(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    is_active: bool
    is_default: bool
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True
