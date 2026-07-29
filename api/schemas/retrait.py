from pydantic import BaseModel
from typing import Optional


class RetraitCreate(BaseModel):
    client_id: str
    amount: float
    warehouse_id: Optional[str] = None
    note: Optional[str] = None


class RetraitRead(BaseModel):
    id: str
    client_id: str
    amount: float
    warehouse_id: Optional[str] = None
    note: Optional[str] = None

    class Config:
        from_attributes = True
