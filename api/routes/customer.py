from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from api.ws_manager import manager
from sqlalchemy.orm import Session
from typing import List
from api.services.customer_service import CustomerService
from api.schemas.customer import CustomerCreate, CustomerRead, CustomerUpdate
from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.models.User import User

router = APIRouter(prefix="", tags=['Customers'])


@router.post("/customers/", response_model=CustomerRead)
def create_customer(
    data: CustomerCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CUSTOMERS_CREATE)),
):
    customer = CustomerService(db, tenant_id=current_user.tenant_id).create(data)
    # Clients : données partagées par le tenant (pas de dépôt).
    background_tasks.add_task(manager.notify, current_user.tenant_id, None, ["customer"])
    return customer


@router.get("/customers/", response_model=List[CustomerRead])
def list_customers(
    search: str | None = None,
    warehouse_id: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CUSTOMERS_READ)),
):
    return CustomerService(db, tenant_id=current_user.tenant_id).list(
        search=search, warehouse_id=warehouse_id,
    )


@router.get("/customers/{customer_id}", response_model=CustomerRead)
def get_customer(
    customer_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CUSTOMERS_READ)),
):
    customer = CustomerService(db, tenant_id=current_user.tenant_id).get(customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")
    return customer


@router.put("/customers/{customer_id}", response_model=CustomerRead)
def update_customer(
    customer_id: str,
    data: CustomerUpdate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CUSTOMERS_UPDATE)),
):
    customer = CustomerService(db, tenant_id=current_user.tenant_id).update(customer_id, data)
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")
    background_tasks.add_task(manager.notify, current_user.tenant_id, None, ["customer"])
    return customer


@router.delete("/customers/{customer_id}", response_model=dict)
def delete_customer(
    customer_id: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CUSTOMERS_DELETE)),
):
    success = CustomerService(db, tenant_id=current_user.tenant_id).delete(customer_id)
    if not success:
        raise HTTPException(status_code=404, detail="Customer not found")
    background_tasks.add_task(manager.notify, current_user.tenant_id, None, ["customer"])
    return {"ok": True}
