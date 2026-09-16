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
from api.models.Warehouse import Warehouse
from api.models.StockMovement import StockMovement, StockType
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


@pytest.fixture()
def warehouse(db, tenant):
    w = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(w)
    db.flush()
    return w


@pytest.fixture()
def warehouse2(db, tenant):
    w = Warehouse(tenant_id=tenant.id, name="Dépôt 2", is_active=True, is_default=False)
    db.add(w)
    db.flush()
    return w


def _make_product(db, tenant, category, name, warehouse_id=None, barcode=None):
    p = Product(name=name, category_id=category.id, sale_price=100,
                purchase_price=50, tenant_id=tenant.id, barcode=barcode,
                warehouse_id=warehouse_id)
    db.add(p)
    db.flush()
    return p


def test_create_duplicate_barcode_rejected_with_clear_message(db, tenant, category, warehouse):
    _make_product(db, tenant, category, "Produit A", warehouse.id, barcode="123456")
    svc = ProductService(db, tenant_id=tenant.id)

    with pytest.raises(HTTPException) as exc:
        svc.create(ProductCreate(
            name="Produit B", purchase_price=10, sale_price=20,
            alert_stock=5, category_id=category.id, warehouse_id=warehouse.id,
            barcode="123456",
        ))

    assert exc.value.status_code == 400
    assert "123456" in exc.value.detail


def test_update_duplicate_barcode_rejected_with_clear_message(db, tenant, category, warehouse):
    _make_product(db, tenant, category, "Produit A", warehouse.id, barcode="123456")
    p2 = _make_product(db, tenant, category, "Produit B", warehouse.id, barcode="789")
    svc = ProductService(db, tenant_id=tenant.id)

    with pytest.raises(HTTPException) as exc:
        svc.update(p2.id, ProductUpdate(
            name="Produit B", purchase_price=10, sale_price=20,
            alert_stock=5, category_id=category.id, warehouse_id=warehouse.id,
            barcode="123456",
        ))

    assert exc.value.status_code == 400
    assert "123456" in exc.value.detail
    db.refresh(p2)
    assert p2.barcode == "789"  # inchangé, pas de commit partiel


def test_update_duplicate_name_rejected_with_clear_message(db, tenant, category, warehouse):
    _make_product(db, tenant, category, "Produit A", warehouse.id)
    p2 = _make_product(db, tenant, category, "Produit B", warehouse.id)
    svc = ProductService(db, tenant_id=tenant.id)

    with pytest.raises(HTTPException) as exc:
        svc.update(p2.id, ProductUpdate(
            name="Produit A", purchase_price=10, sale_price=20,
            alert_stock=5, category_id=category.id, warehouse_id=warehouse.id,
        ))

    assert exc.value.status_code == 400
    assert "Produit A" in exc.value.detail


def test_update_keeping_same_barcode_is_allowed(db, tenant, category, warehouse):
    p = _make_product(db, tenant, category, "Produit A", warehouse.id, barcode="123456")
    svc = ProductService(db, tenant_id=tenant.id)

    updated = svc.update(p.id, ProductUpdate(
        name="Produit A", purchase_price=15, sale_price=25,
        alert_stock=5, category_id=category.id, warehouse_id=warehouse.id,
        barcode="123456",
    ))

    assert updated.sale_price == 25


def test_change_warehouse_blocked_once_a_sale_exists(db, tenant, category, warehouse, warehouse2):
    p = _make_product(db, tenant, category, "Produit A", warehouse.id)
    db.add(StockMovement(
        product_id=p.id, tenant_id=tenant.id, warehouse_id=warehouse.id,
        type=StockType.out, quantity=-2, source_type="SALE",
    ))
    db.commit()
    svc = ProductService(db, tenant_id=tenant.id)

    with pytest.raises(HTTPException) as exc:
        svc.update(p.id, ProductUpdate(
            name="Produit A", purchase_price=15, sale_price=25,
            alert_stock=5, category_id=category.id, warehouse_id=warehouse2.id,
        ))

    assert exc.value.status_code == 400
    db.refresh(p)
    assert p.warehouse_id == warehouse.id  # inchangé


def test_change_warehouse_migrates_stock_when_no_sale_yet(db, tenant, category, warehouse, warehouse2):
    p = _make_product(db, tenant, category, "Produit A", warehouse.id)
    db.add(StockMovement(
        product_id=p.id, tenant_id=tenant.id, warehouse_id=warehouse.id,
        type=StockType.in_, quantity=10, source_type="adjustment",
    ))
    db.commit()
    svc = ProductService(db, tenant_id=tenant.id)

    updated = svc.update(p.id, ProductUpdate(
        name="Produit A", purchase_price=15, sale_price=25,
        alert_stock=5, category_id=category.id, warehouse_id=warehouse2.id,
    ))

    assert updated.warehouse_id == warehouse2.id
    assert updated.stock_migration_note is not None
    movements = db.query(StockMovement).filter(StockMovement.product_id == p.id).all()
    assert all(m.warehouse_id == warehouse2.id for m in movements)


def test_locked_product_cannot_be_modified(db, tenant, category, warehouse):
    p = _make_product(db, tenant, category, "Produit A", warehouse.id)
    p.is_locked = True
    db.commit()
    svc = ProductService(db, tenant_id=tenant.id)

    with pytest.raises(HTTPException) as exc:
        svc.update(p.id, ProductUpdate(
            name="Produit A", purchase_price=15, sale_price=999,
            alert_stock=5, category_id=category.id, warehouse_id=warehouse.id,
            is_locked=True,
        ))

    assert exc.value.status_code == 400
    db.refresh(p)
    assert p.sale_price == 100  # inchangé


def test_locked_product_can_still_be_unlocked(db, tenant, category, warehouse):
    p = _make_product(db, tenant, category, "Produit A", warehouse.id)
    p.is_locked = True
    db.commit()
    svc = ProductService(db, tenant_id=tenant.id)

    # Reenvoie les memes valeurs (comme le fait l'UI de deverrouillage),
    # seul is_locked change effectivement.
    updated = svc.update(p.id, ProductUpdate(
        name="Produit A", purchase_price=50, sale_price=100,
        alert_stock=p.alert_stock, category_id=category.id, warehouse_id=warehouse.id,
        is_locked=False,
    ))

    assert updated.is_locked is False
