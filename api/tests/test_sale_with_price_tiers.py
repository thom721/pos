"""Vente complète (create_sale) utilisant un palier de prix — pas seulement
price_tier_service.tier_price() en isolation (déjà couvert par
test_price_tiers.py). Vérifie que le prix du palier atteint est bien celui
réellement enregistré sur la vente, et que le serveur l'impose même si le
client envoie un unit_price différent (le serveur fait foi — voir le
commentaire dans sale_service.py:608-613)."""
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
from api.services import sale_service, price_tier_service


class _T:
    def __init__(self, q, p):
        self.min_quantity = q
        self.price = p


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
def warehouse(db, tenant):
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt A", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    return wh


@pytest.fixture()
def category(db, tenant):
    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    return cat


@pytest.fixture()
def product_with_tiers(db, tenant, warehouse, category):
    p = Product(
        name="Fiesta", category_id=category.id, sale_price=1800,
        tenant_id=tenant.id, warehouse_id=warehouse.id,
    )
    db.add(p)
    db.flush()
    db.add(StockMovement(
        product_id=p.id, type=StockType.in_, quantity=100,
        tenant_id=tenant.id, warehouse_id=warehouse.id,
    ))
    db.commit()
    price_tier_service.set_tiers(db, tenant.id, p.id, warehouse.id, [
        _T(3, 1700), _T(12, 1600),
    ])
    return p


def _sale_data(product, warehouse, quantity, unit_price=0):
    # unit_price=0 simule un client qui laisse le serveur résoudre le prix
    # (cas normal : catalogue ou palier) — voir sale_service.py:608-617.
    return SaleCreate(
        paid_amount=0,
        payment_method="CASH",
        warehouse_id=warehouse.id,
        items=[SaleItemInput(
            product_id=product.id, quantity=quantity,
            unit_price=unit_price, subtotal=0,
        )],
    )


def test_sale_below_first_tier_uses_catalog_price(db, tenant, warehouse, product_with_tiers):
    sale = sale_service.create_sale(
        db, _sale_data(product_with_tiers, warehouse, 2), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    item = sale.items[0]
    assert float(item.unit_price) == 1800.0
    assert float(item.subtotal) == 3600.0


def test_sale_at_first_tier_uses_tier_price(db, tenant, warehouse, product_with_tiers):
    sale = sale_service.create_sale(
        db, _sale_data(product_with_tiers, warehouse, 3), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    item = sale.items[0]
    assert float(item.unit_price) == 1700.0
    assert float(item.subtotal) == 5100.0


def test_sale_at_higher_tier_uses_highest_reached_tier(db, tenant, warehouse, product_with_tiers):
    sale = sale_service.create_sale(
        db, _sale_data(product_with_tiers, warehouse, 15), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    item = sale.items[0]
    assert float(item.unit_price) == 1600.0
    assert float(item.subtotal) == 24000.0


def test_server_tier_price_overrides_client_sent_unit_price(db, tenant, warehouse, product_with_tiers):
    """Le client envoie un unit_price différent (ex: prix affiché périmé ou
    manipulé) — le serveur impose quand même le prix du palier atteint."""
    sale = sale_service.create_sale(
        db, _sale_data(product_with_tiers, warehouse, 3, unit_price=9999),
        user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    item = sale.items[0]
    assert float(item.unit_price) == 1700.0
