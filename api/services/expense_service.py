from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_
from datetime import datetime

from api.models.Expense import Expense
from api.schemas.expense import ExpenseCreate, ExpenseUpdate
from api.schemas.common import PaginationMeta
from api.core.dt_coerce import now_local


def _serialize(e: Expense) -> dict:
    return {
        "id":             e.id,
        "description":    e.description,
        "category":       e.category,
        "amount":         float(e.amount),
        "expense_date":   e.expense_date,
        "warehouse_id":   e.warehouse_id,
        "warehouse_name": e.warehouse.name if e.warehouse else None,
        "user_id":        e.user_id,
        "user_name":      f"{e.user.fname} {e.user.lname}".strip() if e.user else None,
        "created_at":     e.created_at,
    }


def list_expenses(
    db: Session,
    page: int = 1,
    limit: int = 20,
    search: str | None = None,
    category: str | None = None,
    warehouse_id: str | None = None,
    date_from: datetime | None = None,
    date_to: datetime | None = None,
    tenant_id: str | None = None,
):
    query = db.query(Expense).options(
        joinedload(Expense.warehouse),
        joinedload(Expense.user),
    )

    if tenant_id:
        query = query.filter(Expense.tenant_id == tenant_id)
    if warehouse_id:
        query = query.filter(Expense.warehouse_id == warehouse_id)
    if category:
        query = query.filter(Expense.category == category)
    if search:
        query = query.filter(
            or_(
                Expense.description.ilike(f"%{search}%"),
                Expense.category.ilike(f"%{search}%"),
            )
        )
    if date_from:
        query = query.filter(Expense.expense_date >= date_from)
    if date_to:
        query = query.filter(Expense.expense_date <= date_to)

    total = query.count()
    rows = (
        query.order_by(Expense.expense_date.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )
    pages = max(1, (total + limit - 1) // limit)

    return {
        "data": [_serialize(e) for e in rows],
        "meta": PaginationMeta(page=page, limit=limit, total=total, pages=pages),
    }


def get_expense(db: Session, expense_id: str, tenant_id: str | None = None) -> Expense | None:
    q = db.query(Expense).filter(Expense.id == expense_id)
    if tenant_id:
        q = q.filter(Expense.tenant_id == tenant_id)
    return q.first()


def create_expense(
    db: Session,
    data: ExpenseCreate,
    tenant_id: str | None,
    user_id: str | None,
) -> dict:
    expense = Expense(
        tenant_id=tenant_id,
        user_id=user_id,
        description=data.description,
        category=data.category,
        amount=data.amount,
        expense_date=data.expense_date or now_local(),
        warehouse_id=data.warehouse_id,
    )
    db.add(expense)
    db.commit()
    db.refresh(expense)
    return _serialize(expense)


def update_expense(
    db: Session,
    expense_id: str,
    data: ExpenseUpdate,
    tenant_id: str | None = None,
) -> dict | None:
    expense = get_expense(db, expense_id, tenant_id)
    if not expense:
        return None
    for key, value in data.dict(exclude_unset=True).items():
        setattr(expense, key, value)
    db.commit()
    db.refresh(expense)
    return _serialize(expense)


def delete_expense(db: Session, expense_id: str, tenant_id: str | None = None) -> bool:
    expense = get_expense(db, expense_id, tenant_id)
    if not expense:
        return False
    db.delete(expense)
    db.commit()
    return True
