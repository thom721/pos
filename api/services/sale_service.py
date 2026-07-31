import logging
from decimal import Decimal
from sqlalchemy.orm import Session, joinedload, selectinload
from sqlalchemy.exc import IntegrityError
from sqlalchemy import or_, func
from fastapi import HTTPException
from datetime import datetime, timezone

from api.models.Sale import Sale
from api.models.SaleItem import SaleItem
from api.models.Product import Product
from api.models.StockMovement import StockMovement
from api.models.Payment import Payment
from api.models.Customer import Customer
from api.models.User import User as UserModel
from api.models.Discount import DiscountScope
from api.services.warehouse_helper import resolve_warehouse_id
from api.services.discount_service import resolve_discount, get_active_automatic_receipt_discount
from api.services.stock_service import record_stock_movement

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
    cashier_id: str | None = None,
    warehouse_id: str | None = None,
):
    query = (
        db.query(Sale)
        .options(
            joinedload(Sale.customer),
            joinedload(Sale.user),
            joinedload(Sale.discount_catalog),
            selectinload(Sale.items).joinedload(SaleItem.product).joinedload(Product.category),
            selectinload(Sale.items).joinedload(SaleItem.discount_catalog),
            selectinload(Sale.payments),
        )
    )

    if tenant_id:
        query = query.filter(Sale.tenant_id == tenant_id)

    if cashier_id:
        query = query.filter(Sale.user_id == cashier_id)

    if warehouse_id:
        query = query.filter(Sale.warehouse_id == warehouse_id)

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
        if date_from.tzinfo is None:
            date_from = date_from.replace(tzinfo=timezone.utc)
        query = query.filter(Sale.created_at >= date_from)

    if date_to:
        if date_to.tzinfo is None:
            date_to = date_to.replace(tzinfo=timezone.utc)
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
            joinedload(Sale.discount_catalog),
            selectinload(Sale.items).joinedload(SaleItem.product).joinedload(Product.category),
            selectinload(Sale.items).joinedload(SaleItem.discount_catalog),
            selectinload(Sale.payments),
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
        record_stock_movement(
            db,
            product_id=old_item.product_id,
            user_id=user_id,
            tenant_id=tenant_id,
            type=StockType.in_,
            quantity=float(old_item.quantity),
            source_type="sale_edit_revert",
            source_id=sale.id,
            note="Correction vente — réversion anciens articles",
        )

    # 2. Delete old items
    for old_item in sale.items:
        db.delete(old_item)
    db.flush()

    # 3. New items + stock OUT
    new_total = 0.0
    new_item_discount_total = Decimal(0)
    for item in data.items:
        product = new_products.get(str(item.product_id))
        if not product:
            raise HTTPException(404, f"Produit introuvable: {item.product_id}")
        unit_price = item.unit_price if item.unit_price else product.sale_price
        subtotal = unit_price * item.quantity
        new_total += subtotal

        item_amount, item_disc_id = resolve_discount(
            db,
            getattr(item, "discount_id", None),
            getattr(item, "discount", 0),
            {DiscountScope.item, DiscountScope.both},
            subtotal,
            quantity=item.quantity,
            product_id=product.id,
        )
        new_item_discount_total += item_amount

        db.add(SaleItem(
            sale_id=sale.id,
            product_id=product.id,
            quantity=item.quantity,
            unit_price=unit_price,
            original_price=product.sale_price,
            subtotal=subtotal,
            discount=item_amount,
            discount_id=item_disc_id,
            tenant_id=tenant_id,
        ))
        record_stock_movement(
            db,
            product_id=product.id,
            user_id=user_id,
            tenant_id=tenant_id,
            type=StockType.out,
            quantity=-item.quantity,
            source_type="SALE",
            source_id=sale.id,
            note="Vente POS (modification)",
        )

    # 4. Recalculate totals
    net_before_receipt_discount = Decimal(str(new_total)) - new_item_discount_total
    receipt_discount, receipt_discount_id = resolve_discount(
        db,
        getattr(data, "discount_id", None),
        data.discount,
        {DiscountScope.receipt, DiscountScope.both},
        net_before_receipt_discount,
    )
    discount = float(receipt_discount)
    final = float(net_before_receipt_discount - receipt_discount)
    sale.total_amount = new_total
    sale.discount = discount
    sale.discount_id = receipt_discount_id
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
    warehouse_id: str | None = None,
    current_user=None,
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
    item_discounts: list[tuple[Decimal, str | None]] = []
    item_discount_total = Decimal(0)

    # 1️⃣ Vérification stock + calcul total + résolution des rabais par article
    for item in data.items:
        product = products.get(str(item.product_id))

        if not product:
            raise HTTPException(404, "Produit introuvable")

        if float(product.available_quantity) < item.quantity:
            raise HTTPException(
                400,
                f"Stock insuffisant pour {product.name}"
            )

        unit_price = item.unit_price if item.unit_price else product.sale_price
        subtotal = unit_price * item.quantity
        total += subtotal

        amount, disc_id = resolve_discount(
            db,
            getattr(item, "discount_id", None),
            getattr(item, "discount", 0),
            {DiscountScope.item, DiscountScope.both},
            subtotal,
            quantity=item.quantity,
            product_id=product.id,
        )
        item_discounts.append((amount, disc_id))
        item_discount_total += amount

    net_before_receipt_discount = Decimal(str(total)) - item_discount_total

    receipt_discount, receipt_discount_id = resolve_discount(
        db,
        getattr(data, "discount_id", None),
        data.discount,
        {DiscountScope.receipt, DiscountScope.both},
        net_before_receipt_discount,
    )
    if receipt_discount == 0 and not receipt_discount_id:
        auto = get_active_automatic_receipt_discount(db, tenant_id)
        if auto:
            from api.services.discount_service import compute_amount as _compute_amount
            receipt_discount = _compute_amount(auto, net_before_receipt_discount)
            receipt_discount_id = auto.id

    discount = float(receipt_discount)
    total_after_discount = float(net_before_receipt_discount - receipt_discount)

    # Fidélisation — rédemption : le client utilise son solde pour réduire ce
    # qu'il reste à payer par le moyen de paiement choisi (ne le remplace pas).
    # Clampé silencieusement (comme resolve_discount/compute_amount) plutôt que
    # rejeté — un solde qui a changé entre l'affichage et la soumission ne doit
    # pas faire échouer toute la vente.
    loyalty_redeemed = Decimal(0)
    customer = None
    requested_redeem = Decimal(str(getattr(data, "loyalty_redeemed", 0) or 0))
    if data.customer_id:
        customer = db.query(Customer).filter(Customer.id == str(data.customer_id)).first()
    if requested_redeem > 0 and customer:
        loyalty_redeemed = min(
            requested_redeem,
            Decimal(customer.loyalty_balance or 0),
            Decimal(str(total_after_discount)),
        )

    remaining_after_loyalty = total_after_discount - float(loyalty_redeemed)
    paid = data.paid_amount or 0
    # The register keeps at most the sale amount; excess cash is given back as
    # change. That excess is stored on the sale (change_due) so the receipt
    # can display it — it would otherwise be silently discarded here.
    collected = min(paid, remaining_after_loyalty) if paid > 0 else 0
    change_due = Decimal(str(paid - collected)) if paid > collected else Decimal(0)

    from api.services import config_service as _config_service
    cfg = _config_service.get_or_create(db, tenant_id=tenant_id)

    # Crédit — refuse une vente sous-payée si le poste n'y est pas autorisé.
    # Le frontend bloque déjà ce cas (pos_screen.dart) mais un contrôle
    # uniquement côté app est contournable (appel API direct) ; revérifié ici,
    # seule source de vérité fiable. Même dérogation que le frontend :
    # sales.discount outrepasse la restriction (ex: superviseur). Sans
    # current_user (appel interne, ex: tests), la vérification est ignorée —
    # elle n'a de sens que pour un appel HTTP authentifié.
    if (
        current_user is not None
        and remaining_after_loyalty - collected > 0.005
        and not cfg.allow_cashier_credit
    ):
        from api.core.permissions import has_permission as _has_perm, P
        perms = getattr(current_user, "permissions", None) or []
        roles = getattr(current_user, "roles", None) or []
        if not _has_perm(perms, roles, P.SALES_DISCOUNT):
            raise HTTPException(
                400, "Les ventes à crédit ne sont pas autorisées pour ce poste."
            )

    # Fidélisation — gain : crédite un % du montant de la vente sur le solde
    # du client, HORS portion payée en fidélité (sinon un client gagnerait de
    # la fidélité en dépensant de la fidélité — boucle infinie évitée).
    loyalty_earned = Decimal(0)
    if customer:
        if cfg.loyalty_enabled:
            earn_base = Decimal(str(total_after_discount)) - loyalty_redeemed
            loyalty_earned = (earn_base * Decimal(cfg.loyalty_percent or 0) / 100).quantize(Decimal("0.01"))
            customer.loyalty_balance = Decimal(customer.loyalty_balance or 0) + loyalty_earned
    if loyalty_redeemed > 0 and customer:
        customer.loyalty_balance = Decimal(customer.loyalty_balance or 0) - loyalty_redeemed

    # 2️⃣ Création vente
    # Warehouse : paramètre > payload > dépôt installer du serveur > défaut
    from api.core.config import settings as _cfg
    payload_wh   = getattr(data, 'warehouse_id', None)
    server_wh_id = _cfg.INSTALLER_WAREHOUSE_ID or None
    wh_id = resolve_warehouse_id(
        db, tenant_id,
        warehouse_id or payload_wh or server_wh_id,
    ) if tenant_id else None

    sale = Sale(
        customer_id=str(data.customer_id) if data.customer_id else None,
        user_id=user_id,
        warehouse_id=wh_id,
        reference=f"VNT-{int(datetime.now(timezone.utc).timestamp())}",
        total_amount=total,
        discount=discount,
        discount_id=receipt_discount_id,
        final_amount=total_after_discount,
        paid_amount=collected,
        change_due=change_due,
        loyalty_earned=loyalty_earned,
        loyalty_redeemed=loyalty_redeemed,
        status="UNPAID"
    )
    if tenant_id:
        sale.tenant_id = tenant_id
    # Utiliser l'UUID généré par le client (offline-first) si fourni et valide
    if getattr(data, 'client_id', None):
        import re
        _UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', re.I)
        if _UUID_RE.match(data.client_id):
            sale.id = data.client_id
    db.add(sale)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        # client_id déjà utilisé → retourner la vente existante (idempotence)
        if getattr(data, 'client_id', None):
            existing = db.query(Sale).filter_by(id=data.client_id).first()
            if existing:
                db.refresh(existing)
                return existing
        raise

    # 3️⃣ Items + mouvements stock OUT (réutilise le dict déjà chargé)
    for idx, item in enumerate(data.items):
        product = products[str(item.product_id)]
        applied_price = item.unit_price if item.unit_price else product.sale_price
        item_amount, item_disc_id = item_discounts[idx]

        db.add(SaleItem(
            sale_id=sale.id,
            product_id=product.id,
            quantity=item.quantity,
            unit_price=applied_price,
            original_price=product.sale_price,
            subtotal=applied_price * item.quantity,
            discount=item_amount,
            discount_id=item_disc_id,
            tenant_id=tenant_id,
        ))

        record_stock_movement(
            db,
            product_id=product.id,
            user_id=user_id,
            tenant_id=tenant_id,
            warehouse_id=wh_id,
            type=StockType.out,
            quantity=-item.quantity,
            source_type="SALE",
            source_id=sale.id,
            note="Vente POS",
        )

    # 4️⃣ Paiement + statut + dette
    if collected > 0:
        note = None
        if data.payment_method == "CARD" and data.approval_code:
            note = f"Code approbation terminal : {data.approval_code}"
        pmt = Payment(
            reference_type="SALE",
            reference_id=sale.id,
            amount=collected,
            method=data.payment_method,
            note=note,
            user_id=user_id,
        )
        if tenant_id:
            pmt.tenant_id = tenant_id
        db.add(pmt)

    if loyalty_redeemed > 0:
        loyalty_pmt = Payment(
            reference_type="SALE",
            reference_id=sale.id,
            amount=loyalty_redeemed,
            method="LOYALTY",
            user_id=user_id,
        )
        if tenant_id:
            loyalty_pmt.tenant_id = tenant_id
        db.add(loyalty_pmt)

    # La portion payée en fidélité compte comme "payé" pour le solde/statut/dette.
    total_paid = paid + float(loyalty_redeemed)
    balance = total_after_discount - total_paid

    if balance <= 0:
        sale.status = "PAID"
    elif total_paid == 0:
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
            paid_amount=total_paid,
            balance=balance,
            status="PARTIAL" if total_paid > 0 else "UNPAID"
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
        record_stock_movement(
            db,
            product_id=item.product_id,
            user_id=user_id,
            tenant_id=tenant_id,
            type=StockType.in_,
            quantity=item.quantity,
            source_type="sale_cancel",
            source_id=sale.id,
            note="Annulation vente",
        )

    # Fidélisation — annulation symétrique : reprend le crédit gagné par
    # cette vente, rembourse ce qui avait été utilisé. Se base sur les
    # montants figés sur la vente (pas le taux courant, qui peut avoir changé
    # depuis). N'ajuste rien pour un retour partiel (return_service.py) —
    # limitation assumée, seule l'annulation complète reprend la fidélité.
    if sale.customer_id and (sale.loyalty_earned or sale.loyalty_redeemed):
        customer = db.query(Customer).filter(Customer.id == sale.customer_id).first()
        if customer:
            new_balance = (
                Decimal(customer.loyalty_balance or 0)
                - Decimal(sale.loyalty_earned or 0)
                + Decimal(sale.loyalty_redeemed or 0)
            )
            customer.loyalty_balance = max(new_balance, Decimal(0))

    sale.status = "CANCELLED"
    db.commit()
