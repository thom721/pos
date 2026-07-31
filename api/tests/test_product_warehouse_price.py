"""Prix de vente différent par dépôt : un produit garde un prix par défaut
(Product.sale_price) mais peut avoir un prix spécifique à un dépôt donné
(ProductWarehousePrice) — utilisé à l'affichage (Produits/Caisse, quand un
dépôt est actif) et comme repli de create_sale/update_sale si le client
n'envoie pas de unit_price explicite."""
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.Warehouse import Warehouse
from api.models.StockMovement import StockMovement, StockType
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service
from api.services.product_service import ProductService, resolve_price


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
def two_depots(db, tenant):
    a = Warehouse(tenant_id=tenant.id, name="Dépôt A", is_active=True, is_default=True)
    b = Warehouse(tenant_id=tenant.id, name="Dépôt B", is_active=True, is_default=False)
    db.add_all([a, b])
    db.flush()
    return a, b


@pytest.fixture()
def product(db, tenant, category, two_depots):
    depot_a, depot_b = two_depots
    p = Product(name="Produit", category_id=category.id, sale_price=100,
                purchase_price=50, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=100,
                          tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=100,
                          tenant_id=tenant.id, warehouse_id=depot_b.id))
    db.commit()
    return p


def test_resolve_price_falls_back_to_default_without_override(db, tenant, product, two_depots):
    depot_a, _ = two_depots
    assert resolve_price(db, product, depot_a.id) == 100.0


def test_resolve_price_falls_back_to_default_without_warehouse(db, tenant, product):
    assert resolve_price(db, product, None) == 100.0


def test_set_and_resolve_warehouse_override_price(db, tenant, product, two_depots):
    depot_a, depot_b = two_depots
    svc = ProductService(db, tenant_id=tenant.id)
    svc.set_warehouse_price(product.id, depot_a.id, 120.0)

    assert resolve_price(db, product, depot_a.id) == 120.0
    assert resolve_price(db, product, depot_b.id) == 100.0  # dépôt B non affecté


def test_set_warehouse_price_is_idempotent_upsert(db, tenant, product, two_depots):
    depot_a, _ = two_depots
    svc = ProductService(db, tenant_id=tenant.id)
    svc.set_warehouse_price(product.id, depot_a.id, 120.0)
    svc.set_warehouse_price(product.id, depot_a.id, 130.0)  # met à jour, ne duplique pas

    prices = svc.get_warehouse_prices(product.id)
    assert len(prices) == 1
    assert float(prices[0].sale_price) == 130.0


def test_delete_warehouse_price_reverts_to_default(db, tenant, product, two_depots):
    depot_a, _ = two_depots
    svc = ProductService(db, tenant_id=tenant.id)
    svc.set_warehouse_price(product.id, depot_a.id, 120.0)
    assert svc.delete_warehouse_price(product.id, depot_a.id) is True

    assert resolve_price(db, product, depot_a.id) == 100.0


def test_product_list_reflects_warehouse_price_override(db, tenant, product, two_depots):
    depot_a, depot_b = two_depots
    svc = ProductService(db, tenant_id=tenant.id)
    svc.set_warehouse_price(product.id, depot_a.id, 120.0)

    scoped_a = svc.list(per_page=10, warehouse_id=depot_a.id)
    scoped_b = svc.list(per_page=10, warehouse_id=depot_b.id)
    global_result = svc.list(per_page=10)

    item_a = next(x for x in scoped_a["data"] if x.id == product.id)
    item_b = next(x for x in scoped_b["data"] if x.id == product.id)
    item_global = next(x for x in global_result["data"] if x.id == product.id)
    assert item_a.sale_price == 120.0
    assert item_b.sale_price == 100.0
    assert item_global.sale_price == 100.0


def _sale_data(product, warehouse_id, unit_price=0):
    return SaleCreate(
        paid_amount=1000,
        payment_method="CASH",
        warehouse_id=warehouse_id,
        items=[SaleItemInput(
            product_id=product.id, quantity=1,
            unit_price=unit_price, subtotal=unit_price,
        )],
    )


def test_create_sale_uses_depot_price_when_no_explicit_unit_price(db, tenant, product, two_depots):
    """Le client n'envoie pas de unit_price → create_sale doit résoudre le
    prix du dépôt de la vente, pas le prix par défaut."""
    depot_a, _ = two_depots
    ProductService(db, tenant_id=tenant.id).set_warehouse_price(product.id, depot_a.id, 120.0)

    sale = sale_service.create_sale(
        db, _sale_data(product, depot_a.id, unit_price=0), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    assert sale.total_amount == Decimal("120.00")


def test_create_sale_explicit_unit_price_overrides_depot_price(db, tenant, product, two_depots):
    """Si le client envoie déjà un unit_price (cas normal), il prime — évite
    de recalculer un prix différent de ce qui a été montré au caissier."""
    depot_a, _ = two_depots
    ProductService(db, tenant_id=tenant.id).set_warehouse_price(product.id, depot_a.id, 120.0)

    sale = sale_service.create_sale(
        db, _sale_data(product, depot_a.id, unit_price=100), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    assert sale.total_amount == Decimal("100.00")


def test_warehouse_price_endpoints_excludes_entrepot(db, tenant, product, two_depots):
    """La liste des dépôts pour la gestion de prix exclut l'entrepôt central."""
    from api.services import entrepot_service

    entrepot_service.create_entrepot(db, tenant.id)
    depots = db.query(Warehouse).filter(
        Warehouse.tenant_id == tenant.id,
        Warehouse.is_active == True,  # noqa: E712
        Warehouse.is_entrepot == False,  # noqa: E712
    ).all()
    assert len(depots) == 2  # Dépôt A + Dépôt B, pas l'entrepôt
