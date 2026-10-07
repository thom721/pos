"""Onglet "Produit" / "Service" de l'écran Produits (ProductService.list(
item_type=...)) — voir Product.is_service."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.services.product_service import ProductService


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
def seeded(db, tenant, category):
    db.add(Product(name="Produit A", category_id=category.id, sale_price=10, tenant_id=tenant.id))
    db.add(Product(name="Pressing", category_id=category.id, sale_price=10,
                    tenant_id=tenant.id, is_service=True))
    db.commit()


def test_default_lists_everything(db, tenant, seeded):
    result = ProductService(db, tenant_id=tenant.id).list(per_page=50)
    assert result["total"] == 2


def test_item_type_product_excludes_services(db, tenant, seeded):
    result = ProductService(db, tenant_id=tenant.id).list(per_page=50, item_type="product")
    names = {p.name for p in result["data"]}
    assert names == {"Produit A"}


def test_item_type_service_excludes_products(db, tenant, seeded):
    result = ProductService(db, tenant_id=tenant.id).list(per_page=50, item_type="service")
    names = {p.name for p in result["data"]}
    assert names == {"Pressing"}
