from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class WarehouseCreate(BaseModel):
    name: str
    description: Optional[str] = None
    force: bool = False  # bypass limit check after user confirmation


class WarehouseUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    is_active: Optional[bool] = None
    # Dépôt auquel rattacher cet entrepôt — n'a d'effet que si le warehouse
    # ciblé par l'URL est lui-même un entrepôt (is_entrepot=True). Ellipsis
    # (valeur non fournie) = ne pas toucher ; None explicite = détacher.
    linked_warehouse_id: Optional[str] = None
    unlink_warehouse: bool = False  # true = forcer linked_warehouse_id à None


class WarehouseRead(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    is_active: bool
    is_default: bool
    is_claimed: bool = False
    is_entrepot: bool = False
    linked_warehouse_id: Optional[str] = None
    subscription_ends_at: Optional[datetime] = None
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True
