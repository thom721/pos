from decimal import Decimal

from sqlalchemy.orm import Session, joinedload
from fastapi import HTTPException

from api.core.dt_coerce import now_local
from api.models.Warehouse import Warehouse
from api.models.Product import Product
from api.services.stock_service import record_stock_movement
from api.models.StockMovement import StockType


def list_entrepots(db: Session, tenant_id: str) -> list[Warehouse]:
    return (
        db.query(Warehouse)
        .filter(Warehouse.tenant_id == tenant_id, Warehouse.is_entrepot == True)  # noqa: E712
        .order_by(Warehouse.created_at)
        .all()
    )


def get_entrepot_by_id(db: Session, tenant_id: str, entrepot_id: str) -> Warehouse:
    entrepot = (
        db.query(Warehouse)
        .filter(
            Warehouse.id == entrepot_id,
            Warehouse.tenant_id == tenant_id,
            Warehouse.is_entrepot == True,  # noqa: E712
        )
        .first()
    )
    if not entrepot:
        raise HTTPException(404, "Entrepôt introuvable")
    return entrepot


def create_entrepot(
    db: Session, tenant_id: str, name: str = "Entrepôt", address: str | None = None,
) -> Warehouse:
    """Un tenant peut créer plusieurs entrepôts (pas de plafond, comme les
    caisses). Ne crée PAS de PosRegister ni d'InstallationCode (ce n'est pas
    un dépôt de vente) et ne compte pas dans la facturation des dépôts (voir
    billing.py::_compute_plan_usage) — il a sa propre facturation par
    abonnement (voir _assert_paid ci-dessous). is_claimed=True dès la
    création : l'entrepôt n'est jamais installable comme un poste de vente
    (empêche la génération/le rachat d'un code d'installation — voir
    api/routes/warehouse.py::get_install_code et api/routes/sync.py::redeem_installation_code).
    Pas d'essai gratuit : subscription_ends_at reste NULL tant qu'aucun
    paiement n'a été confirmé — voir _assert_paid()."""
    entrepot = Warehouse(
        tenant_id=tenant_id,
        name=name,
        address=address,
        is_active=True,
        is_default=False,
        is_entrepot=True,
        is_claimed=True,
    )
    db.add(entrepot)
    db.commit()
    db.refresh(entrepot)
    return entrepot


def _assert_paid(entrepot: Warehouse) -> None:
    """Bloque la distribution tant que l'entrepôt n'a pas d'abonnement actif —
    pas d'essai gratuit, contrairement aux caisses (voir _RegisterPaymentSection
    côté Flutter et le point équivalent pour les caisses)."""
    end = entrepot.subscription_ends_at
    if not end or end <= now_local():
        raise HTTPException(
            402,
            "Entrepôt non payé — réglez l'abonnement avant de distribuer le stock.",
        )


def adjust_entrepot_stock(
    db: Session,
    tenant_id: str,
    entrepot_id: str,
    product_id: str,
    quantity: float,
    reason: str | None,
    user_id: str,
) -> Product:
    if quantity == 0:
        raise HTTPException(400, "La quantité doit être non nulle")

    entrepot = get_entrepot_by_id(db, tenant_id, entrepot_id)

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
    entrepot_id: str,
    product_id: str,
    allocations: list[dict],
    user_id: str,
) -> None:
    """Décrémente l'entrepôt et incrémente chaque dépôt cible d'une quantité
    choisie manuellement (pas de répartition automatique) — tout ou rien.
    Bloqué (402) si l'entrepôt n'a pas d'abonnement actif — voir _assert_paid."""
    entrepot = get_entrepot_by_id(db, tenant_id, entrepot_id)
    _assert_paid(entrepot)

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


def transfer_to_entrepot(
    db: Session,
    tenant_id: str,
    entrepot_id: str,
    source_warehouse_id: str,
    product_id: str,
    quantity: float,
    user_id: str,
    reason: str | None = None,
) -> dict:
    """Envoie du stock VERS un entrepôt, depuis n'importe quel autre
    emplacement du tenant — un dépôt de vente classique (« retourner à
    l'entrepôt » depuis la fiche produit) ou un autre entrepôt (transfert
    entrepôt à entrepôt). Mécanisme séparé de distribute() (qui va dans
    l'autre sens, entrepôt → dépôts) — même schéma transactionnel tout-ou-rien.

    Si la source est elle-même un entrepôt non payé, le transfert est bloqué
    (402) — en faire sortir du stock équivaut à une distribution. Recevoir
    dans l'entrepôt cible n'est jamais bloqué (comme adjust_entrepot_stock).
    Retourne un dict exploitable pour un reçu imprimable (audit)."""
    if quantity <= 0:
        raise HTTPException(400, "La quantité doit être positive")

    entrepot = get_entrepot_by_id(db, tenant_id, entrepot_id)

    if source_warehouse_id == entrepot.id:
        raise HTTPException(400, "La source et la destination doivent être différentes")

    source = db.query(Warehouse).filter(
        Warehouse.id == source_warehouse_id,
        Warehouse.tenant_id == tenant_id,
        Warehouse.is_active == True,  # noqa: E712
    ).first()
    if not source:
        raise HTTPException(404, "Emplacement source introuvable")
    if source.is_entrepot:
        _assert_paid(source)

    product = (
        db.query(Product)
        .options(joinedload(Product.stock_movements))
        .filter(Product.id == product_id, Product.tenant_id == tenant_id)
        .first()
    )
    if not product:
        raise HTTPException(404, "Produit introuvable")

    requested = Decimal(str(quantity))
    available = Decimal(str(product.available_quantity_at(source.id)))
    if requested > available:
        raise HTTPException(
            400,
            f"Stock insuffisant à « {source.name} » pour {product.name} "
            f"(disponible: {available}, demandé: {requested})",
        )

    try:
        with db.begin_nested():
            out_mv = record_stock_movement(
                db,
                product_id=product_id,
                user_id=user_id,
                tenant_id=tenant_id,
                warehouse_id=source.id,
                type=StockType.out,
                quantity=-float(requested),
                source_type="entrepot_transfer",
                note=reason or f"Transfert vers l'entrepôt « {entrepot.name} »",
            )
            db.flush()
            in_mv = record_stock_movement(
                db,
                product_id=product_id,
                user_id=user_id,
                tenant_id=tenant_id,
                warehouse_id=entrepot.id,
                type=StockType.in_,
                quantity=requested,
                source_type="entrepot_transfer",
                source_id=out_mv.id,
                note=reason or f"Reçu de « {source.name} »",
            )
        db.commit()
    except Exception:
        db.rollback()
        raise

    db.refresh(in_mv)
    return {
        "movement_id":  in_mv.id,
        "product_name": product.name,
        "quantity":     float(requested),
        "source_name":    source.name,
        "source_address": source.address,
        "target_name":    entrepot.name,
        "target_address": entrepot.address,
        "reason":       reason,
        "created_at":   in_mv.created_at,
    }
