import json
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy import func
from fastapi import HTTPException

from api.models.Product import Product
from api.models.Category import Category
from api.models.StockMovement import StockMovement, StockType
from api.models.InventoryRecord import InventoryRecord


def _stock_map(db: Session, product_ids: list[str], tenant_id: str | None = None) -> dict[str, float]:
    """Return {product_id: current_stock} computed via SQL aggregate."""
    if not product_ids:
        return {}
    query = (
        db.query(
            StockMovement.product_id,
            func.coalesce(func.sum(StockMovement.quantity), 0).label("stock"),
        )
        .filter(StockMovement.product_id.in_(product_ids))
    )
    if tenant_id:
        query = query.filter(StockMovement.tenant_id == tenant_id)
    rows = query.group_by(StockMovement.product_id).all()
    return {r.product_id: float(r.stock) for r in rows}


def get_preview(db: Session, category_ids: list[str] | None = None, tenant_id: str | None = None) -> list[dict]:
    """Return all active products with their current (system) stock for counting."""
    query = (
        db.query(Product)
        .join(Category, Product.category_id == Category.id)
        .filter(Product.is_active == True)
    )
    if tenant_id:
        query = query.filter(Product.tenant_id == tenant_id)
    if category_ids:
        query = query.filter(Product.category_id.in_(category_ids))

    products = query.order_by(Category.name, Product.name).all()
    if not products:
        return []

    pids = [p.id for p in products]
    stocks = _stock_map(db, pids, tenant_id=tenant_id)

    return [
        {
            "product_id": p.id,
            "product_name": p.name,
            "barcode": p.barcode,
            "category": p.category.name,
            "category_id": p.category_id,
            "expected_qty": stocks.get(p.id, 0.0),
        }
        for p in products
    ]


def list_inventories(db: Session, page: int = 1, limit: int = 20, tenant_id: str | None = None) -> dict:
    query = db.query(InventoryRecord)
    if tenant_id:
        query = query.filter(InventoryRecord.tenant_id == tenant_id)
    total = query.count()
    records = (
        query
        .order_by(InventoryRecord.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )
    return {
        "data": records,
        "meta": {"total": total, "page": page, "limit": limit},
    }


def get_inventory(db: Session, inventory_id: str, tenant_id: str | None = None) -> InventoryRecord | None:
    query = db.query(InventoryRecord).filter(InventoryRecord.id == inventory_id)
    if tenant_id:
        query = query.filter(InventoryRecord.tenant_id == tenant_id)
    return query.first()


def create_inventory(db: Session, data, user_id: str, tenant_id: str | None = None) -> InventoryRecord:
    if not data.items:
        raise HTTPException(400, "Aucun produit compté")

    product_ids = [str(item.product_id) for item in data.items]
    stocks = _stock_map(db, product_ids, tenant_id=tenant_id)

    items_summary = []
    discrepancy_count = 0

    # Build record first to get its ID for source_id
    reference = f"INV-{int(datetime.utcnow().timestamp())}"
    record = InventoryRecord(
        reference=reference,
        inventory_type=data.inventory_type,
        status="confirmed",
        notes=data.notes,
        total_products=len(data.items),
        discrepancy_count=0,
        user_id=user_id,
        items_json="[]",
    )
    if tenant_id:
        record.tenant_id = tenant_id
    db.add(record)
    db.flush()  # get record.id

    for item in data.items:
        pid = str(item.product_id)
        product = db.get(Product, pid)
        if not product:
            continue

        expected = stocks.get(pid, 0.0)
        counted = float(item.counted_qty)
        diff = counted - expected

        items_summary.append({
            "product_id": pid,
            "product_name": product.name,
            "barcode": product.barcode,
            "expected_qty": expected,
            "counted_qty": counted,
            "diff": diff,
        })

        if abs(diff) > 0.001:
            discrepancy_count += 1
            mv = StockMovement(
                product_id=pid,
                user_id=user_id,
                type=StockType.adjust,
                quantity=diff,
                source_type="inventory",
                source_id=record.id,
                note=f"Inventaire {reference} — ajustement {expected:+.2f}→{counted:.2f}",
            )
            if tenant_id:
                mv.tenant_id = tenant_id
            db.add(mv)

    record.discrepancy_count = discrepancy_count
    record.items_json = json.dumps(items_summary)

    db.commit()
    db.refresh(record)
    return record
