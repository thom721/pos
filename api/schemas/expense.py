from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class ExpenseCreate(BaseModel):
    description: str
    category: Optional[str] = None
    amount: float
    expense_date: Optional[datetime] = None  # None = maintenant (voir service)
    warehouse_id: Optional[str] = None


class ExpenseUpdate(BaseModel):
    description: Optional[str] = None
    category: Optional[str] = None
    amount: Optional[float] = None
    expense_date: Optional[datetime] = None
    warehouse_id: Optional[str] = None


class ExpenseRead(BaseModel):
    id: str
    description: str
    category: Optional[str] = None
    amount: float
    expense_date: datetime
    warehouse_id: Optional[str] = None
    warehouse_name: Optional[str] = None
    user_id: Optional[str] = None
    user_name: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
