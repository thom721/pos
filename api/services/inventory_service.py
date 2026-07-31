import json
from datetime import datetime, timezone
from sqlalchemy.orm import Session
from fastapi import HTTPException

from api.models.Product import Product
from api.models.Category import Category
from api.models.StockMovement import StockType
from api.models.InventoryRecord import InventoryRecord
from api.services.warehouse_helper import resolve_warehouse_id
from api.services.stock_service import record_stock_movement, stock_map as _stock_map


def get_preview(
    db: Session,
    category_ids: list[str] | None = None,
    tenant_id: str | None = None,
    warehouse_id: str | None = None,
) -> list[dict]:
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
    # Même résolution que create_inventory — l'aperçu doit porter sur le même
    # dépôt que le comptage réel, sinon les deux affichent des totaux différents.
    wh_id = resolve_warehouse_id(db, tenant_id, warehouse_id) if tenant_id else None
    stocks = _stock_map(db, pids, tenant_id=tenant_id, warehouse_id=wh_id)

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


def list_inventories(
    db: Session,
    page: int = 1,
    limit: int = 20,
    tenant_id: str | None = None,
    warehouse_id: str | None = None,
) -> dict:
    query = db.query(InventoryRecord)
    if tenant_id:
        query = query.filter(InventoryRecord.tenant_id == tenant_id)
    if warehouse_id:
        query = query.filter(InventoryRecord.warehouse_id == warehouse_id)
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


def create_inventory(db: Session, data, user_id: str, tenant_id: str | None = None, warehouse_id: str | None = None) -> InventoryRecord:
    if not data.items:
        raise HTTPException(400, "Aucun produit compté")

    wh_id = resolve_warehouse_id(db, tenant_id, warehouse_id or data.warehouse_id) if tenant_id else None
    product_ids = [str(item.product_id) for item in data.items]
    stocks = _stock_map(db, product_ids, tenant_id=tenant_id, warehouse_id=wh_id)

    items_summary = []
    discrepancy_count = 0

    # Build record first to get its ID for source_id
    reference = f"INV-{int(datetime.now(timezone.utc).timestamp())}"
    record = InventoryRecord(
        reference=reference,
        inventory_type=data.inventory_type,
        status="confirmed",
        notes=data.notes,
        total_products=len(data.items),
        discrepancy_count=0,
        user_id=user_id,
        items_json="[]",
        warehouse_id=wh_id,
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

        # _stock_map agrège directement StockMovement.product_id — un produit
        # composé n'a jamais ses propres mouvements (voir record_stock_movement),
        # donc son stock attendu doit venir de la propriété dérivée, pas du map.
        expected = float(product.stock) if product.is_composite else stocks.get(pid, 0.0)
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
            record_stock_movement(
                db,
                product_id=pid,
                user_id=user_id,
                tenant_id=tenant_id,
                warehouse_id=wh_id,
                type=StockType.adjust,
                quantity=diff,
                source_type="inventory",
                source_id=record.id,
                note=f"Inventaire {reference}: ajustement {expected:+.2f}->{counted:.2f}",
            )

    record.discrepancy_count = discrepancy_count
    record.items_json = json.dumps(items_summary)

    db.commit()
    db.refresh(record)
    return record
