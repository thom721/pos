import json
import logging
from fastapi import HTTPException
from sqlalchemy.orm import Session, joinedload

logger = logging.getLogger(__name__)

from api.models.Sale import Sale
from api.models.SaleItem import SaleItem
from api.models.Purchase import Purchase
from api.models.PurchaseItem import PurchaseItem
from api.models.StockMovement import StockMovement, StockType
from api.models.Payment import Payment
from api.models.ReturnRecord import ReturnRecord


# ─────────────────────────────────────────────────────────────────────────────
# Sale return (retour client)
# ─────────────────────────────────────────────────────────────────────────────

def process_sale_return(
    db: Session,
    sale_id: str,
    items: list,
    refund_amount: float,
    user_id: str,
    reason: str | None = None,
):
    sale = (
        db.query(Sale)
        .options(joinedload(Sale.items).joinedload(SaleItem.product))
        .filter(Sale.id == sale_id)
        .first()
    )
    if not sale:
        raise HTTPException(404, "Vente introuvable")

    refund_total = 0.0
    items_summary = []

    for item in items:
        sale_item = db.query(SaleItem).filter(
            SaleItem.sale_id == sale.id,
            SaleItem.product_id == str(item['product_id']),
        ).first()

        if not sale_item:
            raise HTTPException(400, "Article non trouvé dans la vente")

        qty = float(item['quantity'])
        if qty <= 0 or qty > float(sale_item.quantity):
            raise HTTPException(
                400,
                f"Quantité retour invalide ({qty}). "
                f"Quantité vendue : {float(sale_item.quantity)}"
            )

        line_refund = float(sale_item.unit_price) * qty
        refund_total += line_refund

        product_name = (
            sale_item.product.name if sale_item.product else str(sale_item.product_id)
        )
        items_summary.append({
            "product_name": product_name,
            "quantity": qty,
            "unit_price": float(sale_item.unit_price),
            "subtotal": line_refund,
        })

        # Stock comes back IN
        db.add(StockMovement(
            product_id=str(item['product_id']),
            user_id=user_id,
            type=StockType.in_,
            quantity=qty,
            source_type="sale_return",
            source_id=sale.id,
            note=f"Retour client{f' — {reason}' if reason else ''}",
        ))

    # Record refund payment (negative reduces paid_amount)
    actual_refund = refund_amount if refund_amount > 0 else refund_total
    if actual_refund > 0:
        db.add(Payment(
            reference_type="SALE",
            reference_id=sale.id,
            amount=-actual_refund,
            method="CASH",
            note=f"Remboursement retour{f' — {reason}' if reason else ''}",
            user_id=user_id,
        ))

    # Adjust sale totals
    sale.total_amount = max(0, float(sale.total_amount) - refund_total)
    sale.final_amount = max(0, float(sale.final_amount) - refund_total)
    sale.paid_amount  = max(0, float(sale.paid_amount)  - actual_refund)

    # Persist return record for history
    db.add(ReturnRecord(
        return_type="sale",
        reference_id=sale.id,
        doc_reference=sale.reference,
        total_returned=refund_total,
        refund_amount=actual_refund,
        reason=reason,
        user_id=user_id,
        items_json=json.dumps(items_summary),
    ))

    db.commit()
    return refund_total


# ─────────────────────────────────────────────────────────────────────────────
# Purchase return (retour fournisseur)
# ─────────────────────────────────────────────────────────────────────────────

def process_purchase_return(
    db: Session,
    purchase_id: str,
    items: list,
    user_id: str,
    reason: str | None = None,
):
    purchase = (
        db.query(Purchase)
        .options(joinedload(Purchase.items).joinedload(PurchaseItem.product))
        .filter(Purchase.id == purchase_id)
        .first()
    )
    if not purchase:
        raise HTTPException(404, "Achat introuvable")

    return_total = 0.0
    items_summary = []

    for item in items:
        purchase_item = db.query(PurchaseItem).filter(
            PurchaseItem.purchase_id == purchase.id,
            PurchaseItem.product_id == str(item['product_id']),
        ).first()

        if not purchase_item:
            raise HTTPException(400, "Article non trouvé dans l'achat")

        qty = float(item['quantity'])
        if qty <= 0 or qty > float(purchase_item.ordered_qty):
            raise HTTPException(
                400,
                f"Quantité retour invalide ({qty}). "
                f"Quantité achetée : {float(purchase_item.ordered_qty)}"
            )

        line_value = float(purchase_item.unit_price) * qty
        return_total += line_value

        product_name = (
            purchase_item.product.name
            if purchase_item.product
            else str(purchase_item.product_id)
        )
        items_summary.append({
            "product_name": product_name,
            "quantity": qty,
            "unit_price": float(purchase_item.unit_price),
            "subtotal": line_value,
        })

        # Stock goes OUT — quantity négative pour réduire le stock
        db.add(StockMovement(
            product_id=str(item['product_id']),
            user_id=user_id,
            type=StockType.out,
            quantity=-qty,
            source_type="purchase_return",
            source_id=purchase.id,
            note=f"Retour fournisseur{f' — {reason}' if reason else ''}",
        ))

    # Adjust purchase total
    purchase.total_amount = max(0, float(purchase.total_amount) - return_total)

    # Persist return record
    db.add(ReturnRecord(
        return_type="purchase",
        reference_id=purchase.id,
        doc_reference=purchase.reference,
        total_returned=return_total,
        refund_amount=0,
        reason=reason,
        user_id=user_id,
        items_json=json.dumps(items_summary),
    ))

    db.commit()
    return return_total


# ─────────────────────────────────────────────────────────────────────────────
# List returns
# ─────────────────────────────────────────────────────────────────────────────

def list_returns(db: Session, return_type: str | None = None, page: int = 1, limit: int = 20):
    query = db.query(ReturnRecord)
    if return_type:
        query = query.filter(ReturnRecord.return_type == return_type)

    total = query.count()
    records = (
        query
        .order_by(ReturnRecord.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    def serialize(r: ReturnRecord):
        try:
            items = json.loads(r.items_json or "[]")
        except Exception:
            items = []
        return {
            "id": r.id,
            "return_type": r.return_type,
            "doc_reference": r.doc_reference,
            "total_returned": float(r.total_returned or 0),
            "refund_amount": float(r.refund_amount or 0),
            "reason": r.reason,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "items": items,
        }

    return {
        "data": [serialize(r) for r in records],
        "meta": {"total": total, "page": page, "limit": limit},
    }
