import logging
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_, func
from fastapi import HTTPException
from datetime import datetime

from api.models.Sale import Sale
from api.models.SaleItem import SaleItem
from api.models.Product import Product
from api.models.StockMovement import StockMovement
from api.models.Payment import Payment
from api.models.Customer import Customer

logger = logging.getLogger(__name__)


def _inject_returned_qty(db: Session, sales: list) -> None:
    """Attach returned_qty to each SaleItem based on sale_return stock movements."""
    if not sales:
        return
    sale_ids = [s.id for s in sales]
    rows = (
        db.query(
            StockMovement.source_id,
            StockMovement.product_id,
            func.sum(StockMovement.quantity).label("returned_qty"),
        )
        .filter(
            StockMovement.source_type == "sale_return",
            StockMovement.source_id.in_(sale_ids),
        )
        .group_by(StockMovement.source_id, StockMovement.product_id)
        .all()
    )
    return_map = {(r.source_id, r.product_id): float(r.returned_qty) for r in rows}
    for sale in sales:
        for item in (sale.items or []):
            item.returned_qty = return_map.get((sale.id, item.product_id), 0.0)


def list_sales(
    db: Session,
    page: int = 1,
    limit: int = 10,
    search: str | None = None,
    status: str | None = None,
    date_from: datetime | None = None,
    date_to: datetime | None = None,
    tenant_id: str | None = None,
):
    query = (
        db.query(Sale)
        .options(
            joinedload(Sale.customer),
            joinedload(Sale.user),
            joinedload(Sale.items).joinedload(SaleItem.product),
            joinedload(Sale.payments),
        )
    )

    if tenant_id:
        query = query.filter(Sale.tenant_id == tenant_id)

    if search:
        query = query.outerjoin(Customer, Sale.customer_id == Customer.id).filter(
            or_(
                Sale.reference.ilike(f"%{search}%"),
                Customer.name.ilike(f"%{search}%"),
            )
        )

    if status:
        query = query.filter(Sale.status == status)

    if date_from:
        query = query.filter(Sale.created_at >= date_from)

    if date_to:
        query = query.filter(Sale.created_at <= date_to)

    total = query.count()

    sales = (
        query
        .order_by(Sale.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    _inject_returned_qty(db, sales)

    return {
        "data": sales,
        "meta": {
            "page": page,
            "limit": limit,
            "total": total,
            "pages": (total + limit - 1) // limit,
        }
    }


def get_sale(db: Session, sale_id: str, tenant_id: str | None = None):
    query = (
        db.query(Sale)
        .options(
            joinedload(Sale.customer),
            joinedload(Sale.user),
            joinedload(Sale.items).joinedload(SaleItem.product),
            joinedload(Sale.payments),
        )
        .filter(Sale.id == sale_id)
    )
    if tenant_id:
        query = query.filter(Sale.tenant_id == tenant_id)
    sale = query.first()
    if sale:
        _inject_returned_qty(db, [sale])
    return sale

def update_sale(db: Session, sale_id: str, data, user_id: str, tenant_id: str | None = None):
    from api.models.Debt import Debt
    from api.models.StockMovement import StockType

    query = (
        db.query(Sale)
        .options(joinedload(Sale.items))
        .filter(Sale.id == sale_id)
    )
    if tenant_id:
        query = query.filter(Sale.tenant_id == tenant_id)
    sale = query.first()
    if not sale:
        raise HTTPException(404, "Vente introuvable")
    if sale.status == "CANCELLED":
        raise HTTPException(400, "Impossible de modifier une vente annulée")

    if not data.items:
        raise HTTPException(400, "Aucun produit")

    original_paid = float(sale.paid_amount)

    # Pré-charger tous les produits des nouveaux items en une seule requête
    new_product_ids = [str(item.product_id) for item in data.items]
    new_products = {
        p.id: p
        for p in db.query(Product).filter(Product.id.in_(new_product_ids)).all()
    }

    # 1. Revert stock for old items
    for old_item in sale.items:
        mv = StockMovement(
            product_id=old_item.product_id,
            user_id=user_id,
            type=StockType.in_,
            quantity=float(old_item.quantity),
            source_type="sale_edit_revert",
            source_id=sale.id,
            note="Correction vente — réversion anciens articles",
        )
        if tenant_id:
            mv.tenant_id = tenant_id
        db.add(mv)

    # 2. Delete old items
    for old_item in sale.items:
        db.delete(old_item)
    db.flush()

    # 3. New items + stock OUT
    new_total = 0.0
    for item in data.items:
        product = new_products.get(str(item.product_id))
        if not product:
            raise HTTPException(404, f"Produit introuvable: {item.product_id}")
        unit_price = item.unit_price if item.unit_price else product.sale_price
        subtotal = unit_price * item.quantity
        new_total += subtotal

        db.add(SaleItem(
            sale_id=sale.id,
            product_id=product.id,
            quantity=item.quantity,
            unit_price=unit_price,
            original_price=product.sale_price,
            subtotal=subtotal,
        ))
        mv = StockMovement(
            product_id=product.id,
            user_id=user_id,
            type=StockType.out,
            quantity=-item.quantity,
            source_type="SALE",
            source_id=sale.id,
            note="Vente POS (modification)",
        )
        if tenant_id:
            mv.tenant_id = tenant_id
        db.add(mv)

    # 4. Recalculate totals
    discount = data.discount or 0.0
    final = new_total - discount
    sale.total_amount = new_total
    sale.discount = discount
    sale.final_amount = final
    sale.customer_id = str(data.customer_id) if data.customer_id else None

    # 5. Payment adjustment
    diff = final - original_paid  # + means client owes more, - means refund
    additional = data.additional_payment or 0.0

    if diff < 0:
        refund = abs(diff)
        pmt = Payment(
            reference_type="SALE",
            reference_id=sale.id,
            amount=-refund,
            method="CASH",
            note="Remboursement modification vente",
            user_id=user_id,
        )
        if tenant_id:
            pmt.tenant_id = tenant_id
        db.add(pmt)
        new_paid = original_paid - refund
    else:
        new_paid = original_paid + additional
        if additional > 0:
            pmt = Payment(
                reference_type="SALE",
                reference_id=sale.id,
                amount=additional,
                method=data.payment_method or "CASH",
                note="Paiement supplémentaire — modification vente",
                user_id=user_id,
            )
            if tenant_id:
                pmt.tenant_id = tenant_id
            db.add(pmt)

    sale.paid_amount = max(0, new_paid)

    # 6. Status
    balance = final - sale.paid_amount
    if balance <= 0:
        sale.status = "PAID"
    elif sale.paid_amount == 0:
        sale.status = "UNPAID"
    else:
        sale.status = "PARTIAL"

    # 7. Debt
    from api.models.Debt import Debt
    existing_debt = (
        db.query(Debt)
        .filter(Debt.reference_type == "SALE", Debt.reference_id == sale.id)
        .first()
    )
    if balance > 0 and sale.customer_id:
        if existing_debt:
            existing_debt.total_amount = final
            existing_debt.paid_amount = float(sale.paid_amount)
            existing_debt.balance = balance
            existing_debt.status = "PARTIAL" if float(sale.paid_amount) > 0 else "UNPAID"
            existing_debt.partner_id = str(sale.customer_id)
        else:
            debt = Debt(
                reference_type="SALE",
                reference_id=sale.id,
                partner_type="CUSTOMER",
                partner_id=str(sale.customer_id),
                total_amount=final,
                paid_amount=float(sale.paid_amount),
                balance=balance,
                status="PARTIAL" if float(sale.paid_amount) > 0 else "UNPAID",
            )
            if tenant_id:
                debt.tenant_id = tenant_id
            db.add(debt)
    elif existing_debt:
        existing_debt.total_amount = final
        existing_debt.paid_amount = float(sale.paid_amount)
        existing_debt.balance = max(0, balance)
        existing_debt.status = "PAID"

    db.commit()
    db.refresh(sale)
    return sale


def create_sale(
    db: Session,
    data,
    user_id: str,
    tenant_id: str | None = None,
):
    from api.models.Debt import Debt
    from api.models.StockMovement import StockType

    if not data.items:
        raise HTTPException(400, "Aucun produit")

    # Pré-charger tous les produits en une seule requête (évite N+1)
    product_ids = [str(item.product_id) for item in data.items]
    products = {
        p.id: p
        for p in db.query(Product)
        .options(joinedload(Product.stock_movements))
        .filter(Product.id.in_(product_ids))
        .all()
    }

    total = 0

    # 1️⃣ Vérification stock + calcul total
    for item in data.items:
        product = products.get(str(item.product_id))

        if not product:
            raise HTTPException(404, "Produit introuvable")

        if product.stock < item.quantity:
            raise HTTPException(
                400,
                f"Stock insuffisant pour {product.name}"
            )

        unit_price = item.unit_price if item.unit_price else product.sale_price
        total += unit_price * item.quantity

    discount = data.discount or 0
    total_after_discount = total - discount
    paid = data.paid_amount or 0

    # 2️⃣ Création vente
    sale = Sale(
        customer_id=str(data.customer_id) if data.customer_id else None,
        user_id=user_id,
        reference=f"VNT-{int(datetime.utcnow().timestamp())}",
        total_amount=total,
        discount=discount,
        final_amount=total_after_discount,
        paid_amount=paid,
        status="UNPAID"
    )
    if tenant_id:
        sale.tenant_id = tenant_id
    db.add(sale)
    db.flush()

    # 3️⃣ Items + mouvements stock OUT (réutilise le dict déjà chargé)
    for item in data.items:
        product = products[str(item.product_id)]
        applied_price = item.unit_price if item.unit_price else product.sale_price

        db.add(SaleItem(
            sale_id=sale.id,
            product_id=product.id,
            quantity=item.quantity,
            unit_price=applied_price,
            original_price=product.sale_price,
            subtotal=applied_price * item.quantity
        ))

        mv = StockMovement(
            product_id=product.id,
            user_id=user_id,
            type=StockType.out,
            quantity=-item.quantity,
            source_type="SALE",
            source_id=sale.id,
            note="Vente POS"
        )
        if tenant_id:
            mv.tenant_id = tenant_id
        db.add(mv)

    # 4️⃣ Paiement + statut + dette
    if paid > 0:
        note = None
        if data.payment_method == "CARD" and data.approval_code:
            note = f"Code approbation terminal : {data.approval_code}"
        pmt = Payment(
            reference_type="SALE",
            reference_id=sale.id,
            amount=paid,
            method=data.payment_method,
            note=note,
            user_id=user_id,
        )
        if tenant_id:
            pmt.tenant_id = tenant_id
        db.add(pmt)

    balance = total_after_discount - paid

    if balance <= 0:
        sale.status = "PAID"
    elif paid == 0:
        sale.status = "UNPAID"
    else:
        sale.status = "PARTIAL"

    if balance > 0 and data.customer_id:
        debt = Debt(
            reference_type="SALE",
            reference_id=sale.id,
            partner_type="CUSTOMER",
            partner_id=str(data.customer_id),
            total_amount=total_after_discount,
            paid_amount=paid,
            balance=balance,
            status="PARTIAL" if paid > 0 else "UNPAID"
        )
        if tenant_id:
            debt.tenant_id = tenant_id
        db.add(debt)

    db.commit()
    db.refresh(sale)
    return sale


def cancel_sale(db: Session, sale_id: str, user_id: str, tenant_id: str | None = None):
    from api.models.StockMovement import StockType

    query = (
        db.query(Sale)
        .options(joinedload(Sale.items))
        .filter(Sale.id == sale_id)
    )
    if tenant_id:
        query = query.filter(Sale.tenant_id == tenant_id)
    sale = query.first()

    if not sale:
        raise HTTPException(404, "Vente introuvable")

    for item in sale.items:
        mv = StockMovement(
            product_id=item.product_id,
            user_id=user_id,
            type=StockType.in_,
            quantity=item.quantity,
            source_type="sale_cancel",
            source_id=sale.id,
            note="Annulation vente"
        )
        if tenant_id:
            mv.tenant_id = tenant_id
        db.add(mv)

    sale.status = "CANCELLED"
    db.commit()
