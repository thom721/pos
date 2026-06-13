from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_
from datetime import datetime

from api.models.StockMovement import StockMovement 
from api.models.Product import Product


def list_stock_movements(
    db: Session,
    page: int = 1,
    limit: int = 20,
    search: str | None = None,
    stock_type: str | None = None,
    source_type: str | None = None,
    date_from: datetime | None = None,
    date_to: datetime | None = None,
):
    query = (
        db.query(StockMovement)
        .options(
            joinedload(StockMovement.product),
            joinedload(StockMovement.user),
        )
    )

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
