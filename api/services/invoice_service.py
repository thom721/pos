from sqlalchemy.orm import Session, joinedload
from fastapi import HTTPException

from api.models.Invoice import Invoice, InvoiceItem
from api.schemas.invoice import InvoiceCreate, InvoiceUpdate


def list_invoices(db: Session, page: int = 1, limit: int = 20):
    query = (
        db.query(Invoice)
        .options(joinedload(Invoice.items))
        .order_by(Invoice.created_at.desc())
    )
    total = query.count()
    items = query.offset((page - 1) * limit).limit(limit).all()
    return {"data": items, "meta": {"page": page, "limit": limit, "total": total}}


def get_invoice(db: Session, invoice_id: str):
    inv = (
        db.query(Invoice)
        .options(joinedload(Invoice.items))
        .filter(Invoice.id == invoice_id)
        .first()
    )
    if not inv:
        raise HTTPException(404, "Facture introuvable")
    return inv


def create_invoice(db: Session, data: InvoiceCreate, user_id: str):
    existing = db.query(Invoice).filter(Invoice.reference == data.reference).first()
    if existing:
        raise HTTPException(400, f"Référence '{data.reference}' déjà utilisée")

    invoice = Invoice(
        reference=data.reference,
        date=data.date,
        due_date=data.due_date,
        client_id=data.client_id,
        client_name=data.client_name,
        discount=data.discount,
        notes=data.notes,
        currency=data.currency,
        status=data.status,
        user_id=user_id,
    )
    db.add(invoice)
    db.flush()

    for item in data.items:
        db.add(InvoiceItem(
            invoice_id=invoice.id,
            product_id=item.product_id,
            name=item.name,
            quantity=item.quantity,
            unit_price=item.unit_price,
            subtotal=item.subtotal,
        ))

    db.commit()
    db.refresh(invoice)
    return get_invoice(db, invoice.id)


def update_invoice(db: Session, invoice_id: str, data: InvoiceUpdate):
    invoice = get_invoice(db, invoice_id)

    if data.status is not None:
        invoice.status = data.status
    if data.due_date is not None:
        invoice.due_date = data.due_date
    if data.client_id is not None:
        invoice.client_id = data.client_id
    if data.client_name is not None:
        invoice.client_name = data.client_name
    if data.discount is not None:
        invoice.discount = data.discount
    if data.notes is not None:
        invoice.notes = data.notes
    if data.currency is not None:
        invoice.currency = data.currency

    if data.items is not None:
        for item in invoice.items:
            db.delete(item)
        db.flush()
        for item in data.items:
            db.add(InvoiceItem(
                invoice_id=invoice.id,
                product_id=item.product_id,
                name=item.name,
                quantity=item.quantity,
                unit_price=item.unit_price,
                subtotal=item.subtotal,
            ))

    db.commit()
    return get_invoice(db, invoice_id)


def record_payment(db: Session, invoice_id: str, amount: float):
    invoice = get_invoice(db, invoice_id)

    subtotal = float(sum(i.subtotal for i in invoice.items))
    total = subtotal - float(invoice.discount)
    new_paid = float(invoice.paid_amount) + amount

    if new_paid > total:
        new_paid = total

    invoice.paid_amount = new_paid

    if new_paid >= total:
        invoice.status = "paid"
    elif new_paid > 0:
        invoice.status = "partial"

    db.commit()
    return get_invoice(db, invoice_id)


def delete_invoice(db: Session, invoice_id: str):
    invoice = get_invoice(db, invoice_id)
    db.delete(invoice)
    db.commit()
