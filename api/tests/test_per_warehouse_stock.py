"""Le stock produit devient réellement PAR DÉPÔT (au lieu de global) : une
caisse ne peut vendre que ce qui a été tracé pour SON dépôt spécifiquement,
même si le total du tenant (tous dépôts confondus) est suffisant.

Sécurité : les tenants sans aucun Warehouse (mono-dépôt/local) ne sont PAS
concernés — create_sale se rabat alors sur le total global, comportement
strictement inchangé pour ces installations."""
from decimal import Decimal

import pytest
from sqlalchemy import create_engine, text
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
from fastapi import HTTPException


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
def product(db, tenant, category):
    p = Product(name="Produit", category_id=category.id, sale_price=100, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    return p


def _sale_data(product, warehouse_id, quantity=1):
    return SaleCreate(
        paid_amount=100 * quantity,
        payment_method="CASH",
        warehouse_id=warehouse_id,
        items=[SaleItemInput(
            product_id=product.id, quantity=quantity, unit_price=100, subtotal=100 * quantity,
        )],
    )


def test_stock_at_and_available_quantity_at_are_warehouse_scoped(db, tenant, category, two_depots):
    depot_a, depot_b = two_depots
    p = Product(name="P", category_id=category.id, sale_price=10, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=5, tenant_id=tenant.id, warehouse_id=depot_b.id))
    db.commit()
    db.refresh(p)

    assert p.stock == 15  # global inchangé
    assert p.stock_at(depot_a.id) == 10
    assert p.stock_at(depot_b.id) == 5
    assert p.available_quantity_at(depot_a.id) == 10
    assert p.available_quantity_at(depot_b.id) == 5


def test_sale_rejected_at_depot_without_stock_even_if_global_total_suffices(db, tenant, product, two_depots):
    """Le vrai changement de comportement : le dépôt A a tout le stock,
    le dépôt B n'en a aucun — vendre au dépôt B doit être refusé."""
    depot_a, depot_b = two_depots
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.commit()

    # Le total global (10) suffirait pour 1 unité — mais le dépôt B en a 0.
    with pytest.raises(HTTPException) as exc:
        sale_service.create_sale(
            db, _sale_data(product, depot_b.id), user_id="u1", tenant_id=tenant.id,
        )
    assert exc.value.status_code == 400
    assert "dépôt" in exc.value.detail


def test_sale_allowed_at_depot_with_sufficient_stock(db, tenant, product, two_depots):
    depot_a, depot_b = two_depots
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.commit()

    sale = sale_service.create_sale(
        db, _sale_data(product, depot_a.id), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    assert sale is not None

    remaining = db.query(Product).filter(Product.id == product.id).first()
    assert remaining.stock_at(depot_a.id) == 9


def test_sale_falls_back_to_global_stock_when_tenant_has_no_warehouse(db, tenant, product):
    """Non-régression : un tenant sans AUCUN Warehouse (mono-dépôt/local)
    continue de vendre sur le total global — comportement d'avant ce chantier."""
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=5, tenant_id=tenant.id, warehouse_id=None))
    db.commit()

    sale = sale_service.create_sale(
        db, _sale_data(product, None), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    assert sale is not None


def test_cancel_sale_reverts_stock_to_the_sale_warehouse(db, tenant, product, two_depots):
    depot_a, depot_b = two_depots
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.commit()

    sale = sale_service.create_sale(
        db, _sale_data(product, depot_a.id), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    sale_service.cancel_sale(db, sale.id, user_id="u1", tenant_id=tenant.id)

    p = db.query(Product).filter(Product.id == product.id).first()
    assert p.stock_at(depot_a.id) == 10  # revenu à l'état initial
    assert p.stock_at(depot_b.id) == 0   # pas de fuite vers l'autre dépôt


def test_backfill_attaches_null_warehouse_movements_to_tenant_default(db, tenant, category):
    """Mouvements orphelins (warehouse_id NULL) rattachés au dépôt par défaut."""
    from api.main import _backfill_stock_movement_warehouse

    default_wh = Warehouse(tenant_id=tenant.id, name="Principal", is_active=True, is_default=True)
    db.add(default_wh)
    db.flush()

    p = Product(name="P", category_id=category.id, sale_price=10, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=7, tenant_id=tenant.id, warehouse_id=None))
    db.commit()

    engine = db.get_bind()
    _backfill_stock_movement_warehouse(active_engine=engine)

    db.expire_all()
    mv = db.query(StockMovement).filter(StockMovement.product_id == p.id).first()
    assert mv.warehouse_id == default_wh.id


def test_backfill_leaves_tenant_without_default_warehouse_untouched(db, tenant, category):
    """Tenant sans Warehouse du tout (mono-dépôt local) — rien ne change."""
    from api.main import _backfill_stock_movement_warehouse

    p = Product(name="P", category_id=category.id, sale_price=10, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=7, tenant_id=tenant.id, warehouse_id=None))
    db.commit()

    engine = db.get_bind()
    _backfill_stock_movement_warehouse(active_engine=engine)

    db.expire_all()
    mv = db.query(StockMovement).filter(StockMovement.product_id == p.id).first()
    assert mv.warehouse_id is None


def test_backfill_is_idempotent(db, tenant, category):
    from api.main import _backfill_stock_movement_warehouse

    default_wh = Warehouse(tenant_id=tenant.id, name="Principal", is_active=True, is_default=True)
    db.add(default_wh)
    db.flush()
    p = Product(name="P", category_id=category.id, sale_price=10, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=7, tenant_id=tenant.id, warehouse_id=None))
    db.commit()

    engine = db.get_bind()
    _backfill_stock_movement_warehouse(active_engine=engine)
    _backfill_stock_movement_warehouse(active_engine=engine)  # 2e passage — no-op

    db.expire_all()
    mv = db.query(StockMovement).filter(StockMovement.product_id == p.id).first()
    assert mv.warehouse_id == default_wh.id


def test_product_list_scoped_to_warehouse_when_provided(db, tenant, category, two_depots):
    from api.services.product_service import ProductService

    depot_a, depot_b = two_depots
    p = Product(name="P", category_id=category.id, sale_price=10, purchase_price=5, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=3, tenant_id=tenant.id, warehouse_id=depot_b.id))
    db.commit()

    svc = ProductService(db, tenant_id=tenant.id)
    global_result = svc.list(per_page=10)
    scoped_result = svc.list(per_page=10, warehouse_id=depot_a.id)

    global_item = next(x for x in global_result["data"] if x.id == p.id)
    scoped_item = next(x for x in scoped_result["data"] if x.id == p.id)
    assert global_item.stock == 13
    assert scoped_item.stock == 10
