from decimal import Decimal

from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_
from datetime import datetime

from api.models.StockMovement import StockMovement, StockType
from api.models.Product import Product


def record_stock_movement(
    db: Session,
    *,
    product_id: str,
    quantity,
    type: StockType,
    user_id: str | None = None,
    tenant_id: str | None = None,
    warehouse_id: str | None = None,
    source_type: str | None = None,
    source_id: str | None = None,
    note: str | None = None,
    lot_number: str | None = None,
    expiry_date=None,
) -> StockMovement:
    """
    Point d'entrée unique pour créer un mouvement de stock. Si `product_id`
    référence un produit composé (component_product_id renseigné — ex: une
    "Caisse" de 12 "Boîtes"), le mouvement est automatiquement redirigé vers
    le produit composant, avec la quantité multipliée par component_quantity.
    Un produit composé n'a jamais de mouvement de stock à son propre nom —
    son stock est toujours dérivé de celui du composant (Product.stock).

    Tout code qui crée un StockMovement doit passer par cette fonction plutôt
    que d'instancier StockMovement(...) directement, sans quoi la conversion
    composé→composant serait silencieusement ignorée à cet endroit.
    """
    product = db.get(Product, product_id)
    target_id = product_id
    final_quantity = Decimal(str(quantity))
    final_note = note

    if product is not None and product.is_composite:
        target_id = product.component_product_id
        final_quantity = final_quantity * Decimal(str(product.component_quantity))
        suffix = f"(converti depuis « {product.name} »)"
        final_note = f"{note} {suffix}" if note else suffix

    mv = StockMovement(
        product_id=target_id,
        user_id=user_id,
        tenant_id=tenant_id,
        warehouse_id=warehouse_id,
        type=type,
        quantity=final_quantity,
        source_type=source_type,
        source_id=source_id,
        note=final_note,
        lot_number=lot_number,
        expiry_date=expiry_date,
    )
    db.add(mv)
    return mv


def list_stock_movements(
    db: Session,
    page: int = 1,
    limit: int = 20,
    search: str | None = None,
    stock_type: str | None = None,
    source_type: str | None = None,
    date_from: datetime | None = None,
    date_to: datetime | None = None,
    tenant_id: str | None = None,
    warehouse_id: str | None = None,
):
    query = (
        db.query(StockMovement)
        .options(
            joinedload(StockMovement.product),
            joinedload(StockMovement.user),
        )
    )

    if tenant_id:
        query = query.filter(StockMovement.tenant_id == tenant_id)
    if warehouse_id:
        query = query.filter(StockMovement.warehouse_id == warehouse_id)

    # 🔍 Recherche (produit ou note)
    if search:
        query = query.join(Product).filter(
            or_(
                Product.name.ilike(f"%{search}%"),
                StockMovement.note.ilike(f"%{search}%"),
            )
        )

    # 📊 Type IN / OUT
    if stock_type:
        query = query.filter(StockMovement.type == stock_type)

    # 🔗 Source (purchase, sale…)
    if source_type:
        query = query.filter(StockMovement.source_type == source_type)

    # 📆 Date
    if date_from:
        query = query.filter(StockMovement.created_at >= date_from)

    if date_to:
        query = query.filter(StockMovement.created_at <= date_to)

    total = query.count()

    data = (
        query
        .order_by(StockMovement.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    return {
        "data": data,
        "meta": {
            "page": page,
            "limit": limit,
            "total": total,
            "pages": (total + limit - 1) // limit,
        },
    }
