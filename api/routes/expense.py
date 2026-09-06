from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Optional

from api.database import get_db
from api.models.User import User
from api.schemas.expense import ExpenseCreate, ExpenseUpdate, ExpenseRead
from api.schemas.common import PaginatedResponse
from api.services import expense_service
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.ws_manager import manager

router = APIRouter(prefix="/api/expenses", tags=["Expenses"])


@router.get("/", response_model=PaginatedResponse[ExpenseRead])
def list_expenses(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.EXPENSES_READ)),
    page: int = Query(1, ge=1),
    limit: int = Query(20, le=100),
    search: Optional[str] = None,
    category: Optional[str] = None,
    warehouse_id: Optional[str] = None,
    date_from: Optional[datetime] = Query(None),
    date_to: Optional[datetime] = Query(None),
):
    return expense_service.list_expenses(
        db=db, page=page, limit=limit, search=search,
        category=category, warehouse_id=warehouse_id,
        date_from=date_from, date_to=date_to,
        tenant_id=current_user.tenant_id,
    )


@router.post("/", response_model=ExpenseRead)
def create_expense(
    data: ExpenseCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.EXPENSES_CREATE)),
):
    result = expense_service.create_expense(
        db, data, tenant_id=current_user.tenant_id, user_id=current_user.id,
    )
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return result


@router.put("/{expense_id}", response_model=ExpenseRead)
def update_expense(
    expense_id: str,
    data: ExpenseUpdate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.EXPENSES_UPDATE)),
):
    result = expense_service.update_expense(db, expense_id, data, tenant_id=current_user.tenant_id)
    if not result:
        raise HTTPException(status_code=404, detail="Dépense introuvable")
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return result


@router.delete("/{expense_id}", response_model=dict)
def delete_expense(
    expense_id: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.EXPENSES_DELETE)),
):
    success = expense_service.delete_expense(db, expense_id, tenant_id=current_user.tenant_id)
    if not success:
        raise HTTPException(status_code=404, detail="Dépense introuvable")
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return {"ok": True}
