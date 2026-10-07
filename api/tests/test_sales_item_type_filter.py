"""Onglet "Produit" / "Service" de l'écran Ventes (list_sales(item_type=...))
— une vente mixte (produit + service) doit apparaître dans les deux
onglets, pas être cachée des deux ni forcée dans un seul."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.StockMovement import StockMovement, StockType
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service


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
def product(db, tenant, category):
    p = Product(name="Produit", category_id=category.id, sale_price=100, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10, tenant_id=tenant.id))
    db.commit()
    return p


@pytest.fixture()
def service(db, tenant, category):
    p = Product(name="Pressing", category_id=category.id, sale_price=100,
                tenant_id=tenant.id, is_service=True)
    db.add(p)
    db.flush()
    return p


def _sale(product, quantity=1):
    return SaleCreate(
        paid_amount=100 * quantity,
        payment_method="CASH",
        items=[SaleItemInput(
            product_id=product.id, quantity=quantity, unit_price=100, subtotal=100 * quantity,
        )],
    )


def _mixed_sale(product, service):
    return SaleCreate(
        paid_amount=200,
        payment_method="CASH",
        items=[
            SaleItemInput(product_id=product.id, quantity=1, unit_price=100, subtotal=100),
            SaleItemInput(product_id=service.id, quantity=1, unit_price=100, subtotal=100),
        ],
    )


def test_product_only_sale_appears_only_under_product(db, tenant, product, service):
    sale_service.create_sale(db, _sale(product), user_id="u1", tenant_id=tenant.id)
    db.commit()

    product_refs = {s.reference for s in sale_service.list_sales(db, tenant_id=tenant.id, item_type="product")["data"]}
    service_refs = {s.reference for s in sale_service.list_sales(db, tenant_id=tenant.id, item_type="service")["data"]}
    assert len(product_refs) == 1
    assert service_refs == set()


def test_service_only_sale_appears_only_under_service(db, tenant, service):
    sale_service.create_sale(db, _sale(service), user_id="u1", tenant_id=tenant.id)
    db.commit()

    product_refs = sale_service.list_sales(db, tenant_id=tenant.id, item_type="product")["data"]
    service_refs = sale_service.list_sales(db, tenant_id=tenant.id, item_type="service")["data"]
    assert product_refs == []
    assert len(service_refs) == 1


def test_mixed_sale_appears_under_both_tabs(db, tenant, product, service):
    sale = sale_service.create_sale(db, _mixed_sale(product, service), user_id="u1", tenant_id=tenant.id)
    db.commit()

    product_refs = {s.reference for s in sale_service.list_sales(db, tenant_id=tenant.id, item_type="product")["data"]}
    service_refs = {s.reference for s in sale_service.list_sales(db, tenant_id=tenant.id, item_type="service")["data"]}
    assert sale.reference in product_refs
    assert sale.reference in service_refs


def test_no_item_type_filter_returns_everything(db, tenant, product, service):
    sale_service.create_sale(db, _sale(product), user_id="u1", tenant_id=tenant.id)
    db.commit()
    sale_service.create_sale(db, _sale(service), user_id="u1", tenant_id=tenant.id)
    db.commit()

    assert len(sale_service.list_sales(db, tenant_id=tenant.id)["data"]) == 2
