from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from api.database import get_db
from api.models.User import User
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.schemas.invoice import InvoiceCreate, InvoiceRead, InvoiceUpdate, InvoicePaymentInput
from api.services import invoice_service

router = APIRouter(prefix="/api/invoices", tags=["Invoices"])


@router.get("/", response_model=dict)
def list_invoices(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.INVOICES_READ)),
):
    return invoice_service.list_invoices(db, page=page, limit=limit, tenant_id=current_user.tenant_id)


@router.get("/{invoice_id}", response_model=InvoiceRead)
def get_invoice(
    invoice_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.INVOICES_READ)),
):
    return invoice_service.get_invoice(db, invoice_id, tenant_id=current_user.tenant_id)


@router.post("/", response_model=InvoiceRead)
def create_invoice(
    data: InvoiceCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.INVOICES_CREATE)),
):
    return invoice_service.create_invoice(db, data, user_id=current_user.id, tenant_id=current_user.tenant_id)


@router.put("/{invoice_id}", response_model=InvoiceRead)
def update_invoice(
    invoice_id: str,
    data: InvoiceUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.INVOICES_UPDATE)),
):
    return invoice_service.update_invoice(db, invoice_id, data, tenant_id=current_user.tenant_id)


@router.post("/{invoice_id}/payment", response_model=InvoiceRead)
def record_payment(
    invoice_id: str,
    data: InvoicePaymentInput,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PAYMENTS_CREATE)),
):
    return invoice_service.record_payment(db, invoice_id, data.amount, tenant_id=current_user.tenant_id)


@router.delete("/{invoice_id}", response_model=dict)
def delete_invoice(
    invoice_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.INVOICES_DELETE)),
):
    invoice_service.delete_invoice(db, invoice_id, tenant_id=current_user.tenant_id)
    return {"ok": True}
