from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime

from api.database import get_db
from api.models.User import User
from api.schemas.stock import StockMovementRead
from api.schemas.common import PaginatedResponse
from api.services.stock_service import list_stock_movements
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/stock-movements", tags=["Stock"])


@router.get("/", response_model=PaginatedResponse[StockMovementRead])
def read_stock_movements(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.STOCK_READ)),
    page: int = Query(1, ge=1),
    limit: int = Query(20, le=100),
    search: Optional[str] = None,
    stock_type: Optional[str] = Query(None, description="IN | OUT"),
    source_type: Optional[str] = None,
    warehouse_id: Optional[str] = None,
    date_from: Optional[datetime] = Query(None),
    date_to: Optional[datetime] = Query(None),
):
    return list_stock_movements(
        db=db, page=page, limit=limit, search=search,
        stock_type=stock_type, source_type=source_type,
        warehouse_id=warehouse_id,
        date_from=date_from, date_to=date_to,
        tenant_id=current_user.tenant_id,
    )
