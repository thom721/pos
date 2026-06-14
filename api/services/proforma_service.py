from datetime import datetime, timezone
from sqlalchemy.orm import Session, joinedload
from fastapi import HTTPException

from api.models.Proforma import Proforma, ProformaItem
from api.schemas.proforma import ProformaCreate, ProformaUpdate


def list_proformas(db: Session, page: int = 1, limit: int = 20, tenant_id: str | None = None):
    query = (
        db.query(Proforma)
        .options(joinedload(Proforma.items))
        .order_by(Proforma.created_at.desc())
    )
    if tenant_id:
        query = query.filter(Proforma.tenant_id == tenant_id)
    total = query.count()
    items = query.offset((page - 1) * limit).limit(limit).all()
    return {"data": items, "meta": {"page": page, "limit": limit, "total": total}}


def get_proforma(db: Session, proforma_id: str, tenant_id: str | None = None):
    query = (
        db.query(Proforma)
        .options(joinedload(Proforma.items))
        .filter(Proforma.id == proforma_id)
    )
    if tenant_id:
        query = query.filter(Proforma.tenant_id == tenant_id)
    p = query.first()
    if not p:
        raise HTTPException(404, "Proforma introuvable")
    return p


def create_proforma(db: Session, data: ProformaCreate, user_id: str, tenant_id: str | None = None):
    # Check reference uniqueness (tenant-scoped)
    query = db.query(Proforma).filter(Proforma.reference == data.reference)
    if tenant_id:
        query = query.filter(Proforma.tenant_id == tenant_id)
    existing = query.first()
    if existing:
        raise HTTPException(400, f"Référence '{data.reference}' déjà utilisée")

    proforma = Proforma(
        reference=data.reference,
        date=data.date,
        client_id=data.client_id,
        client_name=data.client_name,
        discount=data.discount,
        notes=data.notes,
        currency=data.currency,
        status=data.status,
        user_id=user_id,
    )
    if tenant_id:
        proforma.tenant_id = tenant_id
    db.add(proforma)
    db.flush()

    for item in data.items:
        db.add(ProformaItem(
            proforma_id=proforma.id,
            product_id=item.product_id,
            name=item.name,
            quantity=item.quantity,
            unit_price=item.unit_price,
            subtotal=item.subtotal,
        ))

    db.commit()
    db.refresh(proforma)
    return get_proforma(db, proforma.id, tenant_id=tenant_id)


def update_proforma(db: Session, proforma_id: str, data: ProformaUpdate, tenant_id: str | None = None):
    proforma = get_proforma(db, proforma_id, tenant_id=tenant_id)

    if data.status is not None:
        proforma.status = data.status
    if data.client_id is not None:
        proforma.client_id = data.client_id
    if data.client_name is not None:
        proforma.client_name = data.client_name
    if data.discount is not None:
        proforma.discount = data.discount
    if data.notes is not None:
        proforma.notes = data.notes
    if data.currency is not None:
        proforma.currency = data.currency

    if data.items is not None:
        # Replace items
        for item in proforma.items:
            db.delete(item)
        db.flush()
        for item in data.items:
            db.add(ProformaItem(
                proforma_id=proforma.id,
                product_id=item.product_id,
                name=item.name,
                quantity=item.quantity,
                unit_price=item.unit_price,
                subtotal=item.subtotal,
            ))

    db.commit()
    return get_proforma(db, proforma_id, tenant_id=tenant_id)


def delete_proforma(db: Session, proforma_id: str, tenant_id: str | None = None):
    proforma = get_proforma(db, proforma_id, tenant_id=tenant_id)
    db.delete(proforma)
    db.commit()
