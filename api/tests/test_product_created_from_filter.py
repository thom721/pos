"""ProductService.list(created_from=...) — utilisé par la fiche "nouveau
produit" auto-imprimée côté caisse (app.dart::_checkNewProductFiche) pour ne
récupérer que les produits créés depuis le dernier passage, sans journal
serveur dédié (fonctionne identiquement avec ou sans serveur local, comme
pour les paliers de prix)."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.core.dt_coerce import now_local
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


def test_created_from_excludes_older_products(db, tenant, category):
    now = now_local()
    old = Product(name="Ancien", category_id=category.id, sale_price=10, tenant_id=tenant.id)
    old.created_at = now - timedelta(days=1)
    db.add(old)
    new = Product(name="Nouveau", category_id=category.id, sale_price=10, tenant_id=tenant.id)
    new.created_at = now
    db.add(new)
    db.commit()

    result = ProductService(db, tenant_id=tenant.id).list(
        per_page=50, created_from=now - timedelta(minutes=1),
    )

    names = {p.name for p in result["data"]}
    assert names == {"Nouveau"}
    assert result["total"] == 1


def test_created_from_none_returns_everything(db, tenant, category):
    db.add(Product(name="A", category_id=category.id, sale_price=10, tenant_id=tenant.id))
    db.add(Product(name="B", category_id=category.id, sale_price=10, tenant_id=tenant.id))
    db.commit()

    result = ProductService(db, tenant_id=tenant.id).list(per_page=50, created_from=None)

    assert result["total"] == 2
