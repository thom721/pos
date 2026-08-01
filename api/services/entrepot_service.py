from decimal import Decimal

from sqlalchemy.orm import Session, joinedload
from fastapi import HTTPException

from api.models.Warehouse import Warehouse
from api.models.Product import Product
from api.services.stock_service import record_stock_movement
from api.models.StockMovement import StockType


def get_entrepot(db: Session, tenant_id: str) -> Warehouse | None:
    return (
        db.query(Warehouse)
        .filter(Warehouse.tenant_id == tenant_id, Warehouse.is_entrepot == True)  # noqa: E712
        .first()
    )


def create_entrepot(db: Session, tenant_id: str, name: str = "Entrepôt") -> Warehouse:
    """Idempotent — un seul entrepôt par tenant. Ne crée PAS de PosRegister ni
    d'InstallationCode (ce n'est pas un dépôt de vente) et ne compte pas dans
    la facturation (voir billing.py::_compute_plan_usage). is_claimed=True dès
    la création : l'entrepôt n'est jamais installable comme un poste de vente
    (empêche la génération/le rachat d'un code d'installation — voir
    api/routes/warehouse.py::get_install_code et api/routes/sync.py::redeem_installation_code)."""
    existing = get_entrepot(db, tenant_id)
    if existing:
        return existing

    entrepot = Warehouse(
        tenant_id=tenant_id,
        name=name,
        is_active=True,
        is_default=False,
        is_entrepot=True,
        is_claimed=True,
    )
    db.add(entrepot)
    db.commit()
    db.refresh(entrepot)
    return entrepot


def adjust_entrepot_stock(
    db: Session,
    tenant_id: str,
    product_id: str,
    quantity: float,
    reason: str | None,
    user_id: str,
) -> Product:
    if quantity == 0:
        raise HTTPException(400, "La quantité doit être non nulle")

    entrepot = get_entrepot(db, tenant_id)
    if not entrepot:
        raise HTTPException(404, "Entrepôt introuvable — créez-le d'abord")

    product = db.query(Product).filter(
        Product.id == product_id, Product.tenant_id == tenant_id,
    ).first()
    if not product:
        raise HTTPException(404, "Produit introuvable")

    record_stock_movement(
        db,
        product_id=product_id,
        user_id=user_id,
        tenant_id=tenant_id,
        warehouse_id=entrepot.id,
        type=StockType.in_ if quantity > 0 else StockType.out,
        quantity=quantity,
        source_type="entrepot_adjustment",
        note=reason,
    )
    db.commit()
    db.refresh(product)
    return product


def distribute(
    db: Session,
    tenant_id: str,
    product_id: str,
    allocations: list[dict],
    user_id: str,
) -> None:
    """Décrémente l'entrepôt et incrémente chaque dépôt cible d'une quantité
    choisie manuellement (pas de répartition automatique) — tout ou rien."""
    entrepot = get_entrepot(db, tenant_id)
    if not entrepot:
        raise HTTPException(404, "Entrepôt introuvable — créez-le d'abord")

    allocations = [a for a in allocations if a["quantity"] and a["quantity"] > 0]
    if not allocations:
        raise HTTPException(400, "Aucune quantité à distribuer")

    product = (
        db.query(Product)
        .options(joinedload(Product.stock_movements))
        .filter(Product.id == product_id, Product.tenant_id == tenant_id)
        .first()
    )
    if not product:
        raise HTTPException(404, "Produit introuvable")

    total_requested = sum(Decimal(str(a["quantity"])) for a in allocations)
    available = Decimal(str(product.available_quantity_at(entrepot.id)))
    if total_requested > available:
        raise HTTPException(
            400,
            f"Stock insuffisant à l'entrepôt pour {product.name} "
            f"(disponible: {available}, demandé: {total_requested})",
        )

    target_ids = [a["warehouse_id"] for a in allocations]
    targets = {
        w.id: w for w in db.query(Warehouse).filter(
            Warehouse.id.in_(target_ids),
            Warehouse.tenant_id == tenant_id,
            Warehouse.is_active == True,  # noqa: E712
        ).all()
    }
    for wh_id in target_ids:
        if wh_id == entrepot.id:
            raise HTTPException(400, "Un dépôt cible ne peut pas être l'entrepôt lui-même")
        if wh_id not in targets:
            raise HTTPException(404, f"Dépôt cible introuvable: {wh_id}")

    try:
        with db.begin_nested():
            out_mv = record_stock_movement(
                db,
                product_id=product_id,
                user_id=user_id,
                tenant_id=tenant_id,
                warehouse_id=entrepot.id,
                type=StockType.out,
                quantity=-float(total_requested),
                source_type="entrepot_distribution",
                note=f"Distribution vers {len(allocations)} dépôt(s)",
            )
            db.flush()
            for a in allocations:
                record_stock_movement(
                    db,
                    product_id=product_id,
                    user_id=user_id,
                    tenant_id=tenant_id,
                    warehouse_id=a["warehouse_id"],
                    type=StockType.in_,
                    quantity=a["quantity"],
                    source_type="entrepot_distribution",
                    source_id=out_mv.id,
                    note=f"Reçu de l'entrepôt « {entrepot.name} »",
                )
        db.commit()
    except Exception:
        db.rollback()
        raise
