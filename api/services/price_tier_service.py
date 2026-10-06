"""Paliers de prix par produit et par dépôt (ex: 1 800 à partir de 1 caisse,
1 700 à partir de 3, 1 600 à partir de 12).

Règles :
- un palier par seuil (pas de doublon de quantité minimale) ;
- plus la quantité augmente, plus le prix ne doit pas augmenter ;
- le palier le plus élevé atteint par la quantité de la ligne s'applique à
  toute la ligne (le serveur calcule le prix : le client n'impose pas le sien).
"""
from decimal import Decimal
from typing import Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from api.models.Product import Product
from api.models.ProductPriceTier import ProductPriceTier
from api.models.Warehouse import Warehouse


def _validate(tiers) -> list[tuple[Decimal, Decimal]]:
    pairs = sorted(((Decimal(str(t.min_quantity)), Decimal(str(t.price))) for t in tiers), key=lambda p: p[0])
    seen = set()
    for qty, price in pairs:
        if qty in seen:
            raise HTTPException(400, f"Seuil en double : {qty}")
        seen.add(qty)
    for (q1, p1), (q2, p2) in zip(pairs, pairs[1:]):
        if p2 > p1:
            raise HTTPException(
                400,
                f"Le prix ne doit pas augmenter avec la quantité : {p2} à partir de {q2} "
                f"est plus cher que {p1} à partir de {q1}",
            )
    return pairs


def list_tiers(db: Session, tenant_id, product_id: str, warehouse_id: str) -> list[ProductPriceTier]:
    return (
        db.query(ProductPriceTier)
        .filter(
            ProductPriceTier.tenant_id == tenant_id,
            ProductPriceTier.product_id == product_id,
            ProductPriceTier.warehouse_id == warehouse_id,
        )
        .order_by(ProductPriceTier.min_quantity)
        .all()
    )


def list_all_tiers(db: Session, tenant_id, warehouse_id: str) -> list[ProductPriceTier]:
    return (
        db.query(ProductPriceTier)
        .filter(ProductPriceTier.tenant_id == tenant_id, ProductPriceTier.warehouse_id == warehouse_id)
        .order_by(ProductPriceTier.product_id, ProductPriceTier.min_quantity)
        .all()
    )


def set_tiers(db: Session, tenant_id, product_id: str, warehouse_id: str, tiers) -> list[ProductPriceTier]:
    """Remplace tous les paliers du couple (produit, dépôt)."""
    product = db.query(Product).filter(Product.id == product_id, Product.tenant_id == tenant_id).first()
    if not product:
        raise HTTPException(404, "Produit introuvable")
    wh = db.query(Warehouse).filter(Warehouse.id == warehouse_id, Warehouse.tenant_id == tenant_id).first()
    if not wh:
        raise HTTPException(400, "Dépôt introuvable pour ce tenant")

    pairs = _validate(tiers)
    db.query(ProductPriceTier).filter(
        ProductPriceTier.product_id == product_id,
        ProductPriceTier.warehouse_id == warehouse_id,
    ).delete(synchronize_session=False)
    for qty, price in pairs:
        db.add(ProductPriceTier(
            tenant_id=tenant_id, product_id=product_id, warehouse_id=warehouse_id,
            min_quantity=qty, price=price,
        ))
    db.commit()
    return list_tiers(db, tenant_id, product_id, warehouse_id)


def tier_price(db: Session, product_id: str, warehouse_id: Optional[str], quantity) -> Optional[Decimal]:
    """Prix unitaire du palier atteint par `quantity`, ou None si aucun palier."""
    if not warehouse_id:
        return None
    qty = Decimal(str(quantity))
    tier = (
        db.query(ProductPriceTier)
        .filter(
            ProductPriceTier.product_id == product_id,
            ProductPriceTier.warehouse_id == warehouse_id,
            ProductPriceTier.min_quantity <= qty,
        )
        .order_by(ProductPriceTier.min_quantity.desc())
        .first()
    )
    return Decimal(str(tier.price)) if tier else None
