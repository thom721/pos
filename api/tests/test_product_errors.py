"""ProductService.create()/update() : messages d'erreur clairs pour les
doublons (nom, code-barres) au lieu de laisser remonter un 500 générique
depuis la contrainte unique DB (uq_product_name_tenant/uq_product_barcode_tenant),
qui masquait la vraie cause côté app mobile/web."""
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.schemas.product import ProductCreate, ProductUpdate
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


def _make_product(db, tenant, category, name, barcode=None):
    p = Product(name=name, category_id=category.id, sale_price=100,
                purchase_price=50, tenant_id=tenant.id, barcode=barcode)
    db.add(p)
    db.flush()
    return p


def test_create_duplicate_barcode_rejected_with_clear_message(db, tenant, category):
    _make_product(db, tenant, category, "Produit A", barcode="123456")
    svc = ProductService(db, tenant_id=tenant.id)

    with pytest.raises(HTTPException) as exc:
        svc.create(ProductCreate(
            name="Produit B", purchase_price=10, sale_price=20,
            alert_stock=5, category_id=category.id, barcode="123456",
        ))

    assert exc.value.status_code == 400
    assert "123456" in exc.value.detail


def test_update_duplicate_barcode_rejected_with_clear_message(db, tenant, category):
    _make_product(db, tenant, category, "Produit A", barcode="123456")
    p2 = _make_product(db, tenant, category, "Produit B", barcode="789")
    svc = ProductService(db, tenant_id=tenant.id)

    with pytest.raises(HTTPException) as exc:
        svc.update(p2.id, ProductUpdate(
            name="Produit B", purchase_price=10, sale_price=20,
            alert_stock=5, category_id=category.id, barcode="123456",
        ))

    assert exc.value.status_code == 400
    assert "123456" in exc.value.detail
    db.refresh(p2)
    assert p2.barcode == "789"  # inchangé, pas de commit partiel


def test_update_duplicate_name_rejected_with_clear_message(db, tenant, category):
    _make_product(db, tenant, category, "Produit A")
    p2 = _make_product(db, tenant, category, "Produit B")
    svc = ProductService(db, tenant_id=tenant.id)

    with pytest.raises(HTTPException) as exc:
        svc.update(p2.id, ProductUpdate(
            name="Produit A", purchase_price=10, sale_price=20,
            alert_stock=5, category_id=category.id,
        ))

    assert exc.value.status_code == 400
    assert "Produit A" in exc.value.detail


def test_update_keeping_same_barcode_is_allowed(db, tenant, category):
    p = _make_product(db, tenant, category, "Produit A", barcode="123456")
    svc = ProductService(db, tenant_id=tenant.id)

    updated = svc.update(p.id, ProductUpdate(
        name="Produit A", purchase_price=15, sale_price=25,
        alert_stock=5, category_id=category.id, barcode="123456",
    ))

    assert updated.sale_price == 25
