from decimal import Decimal

from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_, func
from datetime import datetime

from api.models.StockMovement import StockMovement, StockType
from api.models.Product import Product


def stock_map(
    db: Session,
    product_ids: list[str],
    tenant_id: str | None = None,
    warehouse_id: str | None = None,
) -> dict[str, float]:
    """Retourne {product_id: stock} via agrégat SQL, filtré par dépôt si
    fourni. Partagé entre inventory_service (aperçu/comptage) et
    product_service (liste produits par dépôt) — évite de charger tous les
    stock_movements en mémoire pour chaque produit."""
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
    if warehouse_id:
        query = query.filter(StockMovement.warehouse_id == warehouse_id)
    rows = query.group_by(StockMovement.product_id).all()
    return {r.product_id: float(r.stock) for r in rows}


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

    target_product = product

    if product is not None and product.is_composite:
        target_id = product.component_product_id
        target_product = product.component
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


def list_low_stock_products(
    db: Session,
    tenant_id: str,
    warehouse_id: str | None = None,
) -> list[dict]:
    """Produits (non composés, actifs) dont le stock actuel est descendu à ou
    sous leur seuil d'alerte (Product.alert_stock). Les produits composés en
    sont exclus : leur stock dérive toujours de leur composant, qui apparaît
    lui-même dans cette liste s'il est concerné — voir record_stock_movement.
    Utilisé pour l'affichage temps réel (page d'accueil) et pour le digest
    email de fin de journée (api.utils.email.maybe_send_low_stock_digest)."""
    candidates = (
        db.query(Product)
        .filter(
            Product.tenant_id == tenant_id,
            Product.is_active == True,  # noqa: E712
            Product.component_product_id.is_(None),
        )
        .all()
    )
    if not candidates:
        return []
    stocks = stock_map(db, [p.id for p in candidates], tenant_id=tenant_id, warehouse_id=warehouse_id)
    result = []
    for p in candidates:
        current = stocks.get(p.id, 0)
        alert = p.alert_stock or 0
        if current <= alert:
            result.append({"id": p.id, "name": p.name, "stock": current, "alert_stock": alert})
    return result


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
    product_id: str | None = None,
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
    if product_id:
        query = query.filter(StockMovement.product_id == product_id)

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
