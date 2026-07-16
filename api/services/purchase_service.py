import logging
from sqlalchemy.orm import Session, joinedload
from fastapi import HTTPException
from datetime import datetime

logger = logging.getLogger(__name__)
from api.models.Product import Product
from api.models.Payment import Payment
from api.models.StockMovement import StockMovement
from api.models.PurchaseItem import PurchaseItem
from api.models.Purchase import Purchase
from api.models.Supplier import Supplier
from api.models.Debt import Debt
from sqlalchemy import or_, and_
from api.services.warehouse_helper import resolve_warehouse_id



def list_purchases(
    db: Session,
    page: int = 1,
    limit: int = 10,
    search: str | None = None,
    status: str | None = None,
    date_from: datetime | None = None,
    date_to: datetime | None = None,
    tenant_id: str | None = None,
    warehouse_id: str | None = None,
):
    query = (
        db.query(Purchase)
        .options(
            joinedload(Purchase.supplier),
            joinedload(Purchase.user),
            joinedload(Purchase.items).joinedload(PurchaseItem.product),
            joinedload(Purchase.payments),
        )
    )

    if tenant_id:
        query = query.filter(Purchase.tenant_id == tenant_id)
    if warehouse_id:
        query = query.filter(Purchase.warehouse_id == warehouse_id)

    # 🔍 Recherche (reference + supplier)
    if search:
        query = query.join(Supplier).filter(
            or_(
                Purchase.reference.ilike(f"%{search}%"),
                Supplier.name.ilike(f"%{search}%"),
            )
        )

    # 📊 Filtre status
    if status:
        query = query.filter(Purchase.status == status)

    # 📆 Filtre date
    if date_from:
        query = query.filter(Purchase.created_at >= date_from)

    if date_to:
        query = query.filter(Purchase.created_at <= date_to)

    total = query.count()

    purchases = (
        query
        .order_by(Purchase.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    return {
        "data": purchases,
        "meta": {
            "page": page,
            "limit": limit,
            "total": total,
            "pages": (total + limit - 1) // limit,
        }
    }

def get_purchase(db: Session, purchase_id: str, tenant_id: str | None = None):
    query = (
        db.query(Purchase)
        .options(
            joinedload(Purchase.supplier),
            joinedload(Purchase.user),
            joinedload(Purchase.items).joinedload("product"),
            joinedload(Purchase.payments)
        )
        .filter(Purchase.id == purchase_id)
    )
    if tenant_id:
        query = query.filter(Purchase.tenant_id == tenant_id)
    return query.first()


def create_purchase(db: Session, data, user_id: str, tenant_id: str | None = None, warehouse_id: str | None = None):
    if not data.items:
        raise HTTPException(400, "Aucun produit")

    # Pré-charger tous les produits en une seule requête (évite N+1)
    product_ids = [str(item.product_id) for item in data.items]
    products = {
        p.id: p
        for p in db.query(Product).filter(Product.id.in_(product_ids)).all()
    }

    total = 0
    for item in data.items:
        product = products.get(str(item.product_id))
        if not product:
            raise HTTPException(404, "Produit introuvable")
        total += item.unit_price * item.ordered_qty

    if data.paid_amount == 0:
        status = "pending"
    elif data.paid_amount < total:
        status = "partial"
    else:
        status = "paid"

    wh_id = resolve_warehouse_id(db, tenant_id, warehouse_id or data.warehouse_id) if tenant_id else None
    purchase = Purchase(
        supplier_id=str(data.supplier_id),
        user_id=user_id,
        warehouse_id=wh_id,
        reference=f"PUR-{int(datetime.utcnow().timestamp())}",
        total_amount=total,
        paid_amount=data.paid_amount,
        status=status
    )
    if tenant_id:
        purchase.tenant_id = tenant_id
    db.add(purchase)
    db.flush()

    # Items (réutilise le dict déjà chargé)
    for item in data.items:
        product = products[str(item.product_id)]
        db.add(PurchaseItem(
            purchase_id=purchase.id,
            product_id=product.id,
            ordered_qty=item.ordered_qty,
            remaining_qty=item.ordered_qty,
            unit_price=item.unit_price,
            subtotal=item.unit_price * item.ordered_qty
        ))

    # Paiement
    if data.paid_amount > 0:
        pmt = Payment(
            reference_type="PURCHASE",
            reference_id=purchase.id,
            amount=data.paid_amount,
            method="cash",
            user_id=user_id
        )
        if tenant_id:
            pmt.tenant_id = tenant_id
        db.add(pmt)

    if total > data.paid_amount:
        balance = total - data.paid_amount
        debt = Debt(
            reference_type="PURCHASE",
            reference_id=purchase.id,
            partner_type="SUPPLIER",
            partner_id=str(data.supplier_id) if data.supplier_id else None,
            total_amount=total,
            paid_amount=data.paid_amount,
            balance=balance,
            status="UNPAID" if data.paid_amount == 0 else "PARTIAL"
        )
        if tenant_id:
            debt.tenant_id = tenant_id
        db.add(debt)

    db.commit()  # <-- commit ici
    db.refresh(purchase)
    return purchase
