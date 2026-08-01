"""Entrepôt central : reçoit du stock (manuellement ou via réception d'achat),
distribue vers les dépôts du tenant selon une quantité choisie par dépôt, et
n'est jamais compté comme un dépôt de vente facturable."""
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.Warehouse import Warehouse
from api.models.StockMovement import StockMovement, StockType
from api.models.Purchase import Purchase, PurchaseStatus
from api.models.PurchaseItem import PurchaseItem
from api.services import entrepot_service


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def tenant(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    return t


@pytest.fixture()
def category(db, tenant):
    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    return cat


@pytest.fixture()
def depots(db, tenant):
    a = Warehouse(tenant_id=tenant.id, name="Dépôt A", is_active=True, is_default=True)
    b = Warehouse(tenant_id=tenant.id, name="Dépôt B", is_active=True, is_default=False)
    db.add_all([a, b])
    db.flush()
    return a, b


@pytest.fixture()
def product(db, tenant, category):
    p = Product(name="Produit", category_id=category.id, sale_price=100, purchase_price=50, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    return p


def test_create_entrepot_is_idempotent(db, tenant):
    e1 = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt")
    e2 = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt")
    assert e1.id == e2.id
    assert e1.is_entrepot is True
    assert e1.is_default is False


def test_create_entrepot_is_claimed_to_prevent_installation(db, tenant):
    """L'entrepôt n'est pas un poste de vente installable — is_claimed=True
    dès la création empêche GET/POST install-code et redeem-code de lui
    générer/valider un code (voir api/routes/warehouse.py, api/routes/sync.py)."""
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    assert entrepot.is_claimed is True


def test_entrepot_excluded_from_billing_depot_count(db, tenant, depots):
    from api.routes.billing import _compute_plan_usage

    entrepot_service.create_entrepot(db, tenant.id)
    usage = _compute_plan_usage(tenant, db, None)
    # depots = 2 (Dépôt A, Dépôt B) — l'entrepôt n'est pas compté
    assert usage["current_depots"] == 2


def test_manual_adjustment_increases_entrepot_stock(db, tenant, product):
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(
        db, tenant.id, product.id, 20, "Réception manuelle", "u1",
    )
    db.refresh(product)
    assert product.stock_at(entrepot.id) == 20


def test_purchase_receipt_targeting_entrepot_increases_its_stock(db, tenant, product):
    """Réception automatique : aucun code neuf — ReceiptService résout
    n'importe quel warehouse_id actif du tenant, l'entrepôt y compris."""
    from api.schemas.purchase_receipt import PurchaseReceiptCreate, ReceiptItemCreate
    from api.services.ReceiptService import ReceiptService

    entrepot = entrepot_service.create_entrepot(db, tenant.id)

    purchase = Purchase(
        tenant_id=tenant.id, reference="PO-1", total_amount=500,
        warehouse_id=entrepot.id, status=PurchaseStatus.pending,
    )
    db.add(purchase)
    db.flush()
    item = PurchaseItem(
        tenant_id=tenant.id, purchase_id=purchase.id, product_id=product.id,
        ordered_qty=10, unit_price=50, subtotal=500,
    )
    db.add(item)
    db.commit()

    payload = PurchaseReceiptCreate(
        purchase_id=purchase.id,
        warehouse_id=entrepot.id,
        items=[ReceiptItemCreate(
            purchase_item_id=item.id,
            purchase_receipt_id="unused",
            product_id=product.id,
            received_qty=10,
        )],
    )
    ReceiptService(db).receive(payload, user_id="u1", tenant_id=tenant.id)

    db.refresh(product)
    assert product.stock_at(entrepot.id) == 10


def test_distribute_moves_stock_from_entrepot_to_target_depots(db, tenant, product, depots):
    depot_a, depot_b = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(db, tenant.id, product.id, 30, None, "u1")

    entrepot_service.distribute(
        db, tenant.id, product.id,
        [
            {"warehouse_id": depot_a.id, "quantity": 12},
            {"warehouse_id": depot_b.id, "quantity": 8},
        ],
        "u1",
    )

    db.refresh(product)
    assert product.stock_at(entrepot.id) == 10  # 30 - 12 - 8
    assert product.stock_at(depot_a.id) == 12
    assert product.stock_at(depot_b.id) == 8


def test_distribute_rejects_insufficient_entrepot_stock(db, tenant, product, depots):
    depot_a, _ = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(db, tenant.id, product.id, 5, None, "u1")

    with pytest.raises(HTTPException) as exc:
        entrepot_service.distribute(
            db, tenant.id, product.id,
            [{"warehouse_id": depot_a.id, "quantity": 10}],
            "u1",
        )
    assert exc.value.status_code == 400

    db.refresh(product)
    assert product.stock_at(entrepot.id) == 5  # inchangé — rien n'a été déplacé
    assert product.stock_at(depot_a.id) == 0


def test_distribute_rejects_invalid_target_warehouse(db, tenant, product):
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(db, tenant.id, product.id, 30, None, "u1")

    with pytest.raises(HTTPException) as exc:
        entrepot_service.distribute(
            db, tenant.id, product.id,
            [{"warehouse_id": "not-a-real-warehouse", "quantity": 5}],
            "u1",
        )
    assert exc.value.status_code == 404


def test_distribute_rejects_targeting_entrepot_itself(db, tenant, product):
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(db, tenant.id, product.id, 30, None, "u1")

    with pytest.raises(HTTPException) as exc:
        entrepot_service.distribute(
            db, tenant.id, product.id,
            [{"warehouse_id": entrepot.id, "quantity": 5}],
            "u1",
        )
    assert exc.value.status_code == 400
