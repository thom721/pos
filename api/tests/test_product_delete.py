"""ProductService.delete() : SaleItem.product_id et StockMovement.product_id
référencent products.id sans ON DELETE CASCADE — sans contrôle explicite,
supprimer un produit déjà vendu / avec mouvement de stock / utilisé comme
composant d'un autre produit remonterait une IntegrityError SQL brute.
delete() bloque et détaille TOUTES les raisons (pas seulement la première)
dans une réponse structurée, pour que le frontend propose au tenant de
verrouiller le produit ou de tout supprimer explicitement (force_delete)."""
from decimal import Decimal

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.Sale import Sale
from api.models.SaleItem import SaleItem
from api.models.StockMovement import StockMovement, StockType
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


def _make_product(db, tenant, category, name, **kwargs):
    p = Product(name=name, category_id=category.id, sale_price=100,
                purchase_price=50, tenant_id=tenant.id, **kwargs)
    db.add(p)
    db.flush()
    return p


def test_delete_product_without_history_succeeds(db, tenant, category):
    p = _make_product(db, tenant, category, "Produit sans historique")
    svc = ProductService(db, tenant_id=tenant.id)

    assert svc.delete(p.id) is True
    assert db.get(Product, p.id) is None


def test_delete_product_missing_returns_false(db, tenant):
    svc = ProductService(db, tenant_id=tenant.id)
    assert svc.delete("does-not-exist") is False


def test_delete_product_with_sale_history_is_blocked(db, tenant, category):
    p = _make_product(db, tenant, category, "Produit vendu")
    sale = Sale(tenant_id=tenant.id, user_id="u1", reference="VNT-00001",
                total_amount=100, final_amount=100, paid_amount=100)
    db.add(sale)
    db.flush()
    db.add(SaleItem(sale_id=sale.id, product_id=p.id, quantity=1,
                     unit_price=100, subtotal=100))
    db.commit()

    svc = ProductService(db, tenant_id=tenant.id)
    with pytest.raises(HTTPException) as exc:
        svc.delete(p.id)
    assert exc.value.status_code == 400
    detail = exc.value.detail
    assert detail["blocked"] is True
    assert detail["product_name"] == "Produit vendu"
    assert any(r["type"] == "sales" for r in detail["reasons"])
    # Le produit n'est jamais supprimé quand le contrôle bloque
    assert db.get(Product, p.id) is not None


def test_delete_product_with_stock_movement_is_blocked(db, tenant, category):
    p = _make_product(db, tenant, category, "Produit avec mouvement")
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10,
                          tenant_id=tenant.id))
    db.commit()

    svc = ProductService(db, tenant_id=tenant.id)
    with pytest.raises(HTTPException) as exc:
        svc.delete(p.id)
    reasons = exc.value.detail["reasons"]
    assert any(r["type"] == "stock_movements" for r in reasons)


def test_delete_product_used_as_composite_component_is_blocked(db, tenant, category):
    boite = _make_product(db, tenant, category, "Boîte lait")
    _make_product(
        db, tenant, category, "Caisse lait",
        component_product_id=boite.id, component_quantity=Decimal("12"),
    )
    db.commit()

    svc = ProductService(db, tenant_id=tenant.id)
    with pytest.raises(HTTPException) as exc:
        svc.delete(boite.id)
    reasons = exc.value.detail["reasons"]
    composite_reason = next(r for r in reasons if r["type"] == "composite_component")
    assert "Caisse lait" in composite_reason["products"]
    assert db.get(Product, boite.id) is not None


def test_delete_reports_all_blockers_simultaneously(db, tenant, category):
    """Un produit peut cumuler plusieurs raisons — toutes doivent apparaître,
    pas seulement la première trouvée."""
    p = _make_product(db, tenant, category, "Produit multi-bloqué")
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10, tenant_id=tenant.id))
    sale = Sale(tenant_id=tenant.id, user_id="u1", reference="VNT-00001",
                total_amount=10, final_amount=10, paid_amount=10)
    db.add(sale)
    db.flush()
    db.add(SaleItem(sale_id=sale.id, product_id=p.id, quantity=1, unit_price=10, subtotal=10))
    db.commit()

    svc = ProductService(db, tenant_id=tenant.id)
    with pytest.raises(HTTPException) as exc:
        svc.delete(p.id)
    types = {r["type"] for r in exc.value.detail["reasons"]}
    assert types == {"sales", "stock_movements"}


def test_force_delete_removes_stock_movements(db, tenant, category):
    p = _make_product(db, tenant, category, "Produit avec mouvement")
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10, tenant_id=tenant.id))
    db.commit()

    svc = ProductService(db, tenant_id=tenant.id)
    assert svc.force_delete(p.id) is True

    assert db.get(Product, p.id) is None
    assert db.query(StockMovement).filter_by(product_id=p.id).count() == 0


def test_force_delete_detaches_sale_items_but_preserves_history(db, tenant, category):
    """L'historique financier (montants, quantités) n'est jamais touché —
    seule la référence au produit est détachée, avec son nom figé sur
    `label` pour que les reçus restent lisibles après coup."""
    p = _make_product(db, tenant, category, "Lait entier Centrale 2L")
    sale = Sale(tenant_id=tenant.id, user_id="u1", reference="VNT-00001",
                total_amount=100, final_amount=100, paid_amount=100)
    db.add(sale)
    db.flush()
    item = SaleItem(sale_id=sale.id, product_id=p.id, quantity=2, unit_price=50, subtotal=100)
    db.add(item)
    db.commit()

    svc = ProductService(db, tenant_id=tenant.id)
    svc.force_delete(p.id)

    db.refresh(item)
    assert item.product_id is None
    assert item.label == "Lait entier Centrale 2L"
    assert item.quantity == 2
    assert item.subtotal == 100


def test_force_delete_unlinks_dependent_composite_products(db, tenant, category):
    """Un produit composé qui utilisait celui-ci comme composant redevient
    un produit normal (n'empêche plus la suppression, ne casse pas non
    plus le produit composé — il perd juste son stock dérivé)."""
    boite = _make_product(db, tenant, category, "Boîte lait")
    caisse = _make_product(
        db, tenant, category, "Caisse lait",
        component_product_id=boite.id, component_quantity=Decimal("12"),
    )
    db.commit()

    svc = ProductService(db, tenant_id=tenant.id)
    svc.force_delete(boite.id)

    db.refresh(caisse)
    assert caisse.component_product_id is None
    assert caisse.component_quantity is None
    assert caisse.is_composite is False


def test_force_delete_missing_product_returns_false(db, tenant):
    svc = ProductService(db, tenant_id=tenant.id)
    assert svc.force_delete("does-not-exist") is False
