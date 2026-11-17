"""Bug réel : list_stock_movements(stock_type=...) comparait la string brute
reçue de l'API ("IN") directement à la colonne Enum, qui stocke le NOM du
membre SQLAlchemy ("in_", pas sa .value "in") — aucune ligne ne matchait
jamais, donc la fiche de réception auto-imprimée côté caisse (app.dart::
_checkStockReceivingFiche, filtrant 'stock_type': 'IN') ne trouvait jamais
rien. Voir _resolve_stock_type dans stock_service.py."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Category import Category
from api.models.Product import Product
from api.models.StockMovement import StockMovement, StockType
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.services.stock_service import list_stock_movements


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


@pytest.fixture()
def world(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="W", is_active=True, is_default=True)
    cat = Category(tenant_id=t.id, name="C")
    db.add_all([wh, cat])
    db.flush()
    p = Product(tenant_id=t.id, category_id=cat.id, name="P", sale_price=10)
    db.add(p)
    db.flush()
    db.add_all([
        StockMovement(tenant_id=t.id, product_id=p.id, warehouse_id=wh.id, type=StockType.in_, quantity=5),
        StockMovement(tenant_id=t.id, product_id=p.id, warehouse_id=wh.id, type=StockType.out, quantity=2),
        StockMovement(tenant_id=t.id, product_id=p.id, warehouse_id=wh.id, type=StockType.adjust, quantity=-1),
    ])
    db.commit()
    return {"tenant": t, "wh": wh}


@pytest.mark.parametrize("raw", ["IN", "in", "in_"])
def test_in_filter_matches_regardless_of_case(db, world, raw):
    page = list_stock_movements(db, stock_type=raw, tenant_id=world["tenant"].id)
    assert page["meta"]["total"] == 1
    assert page["data"][0].type is StockType.in_


@pytest.mark.parametrize("raw", ["ADJUST", "adjust"])
def test_adjust_filter_matches_regardless_of_case(db, world, raw):
    page = list_stock_movements(db, stock_type=raw, tenant_id=world["tenant"].id)
    assert page["meta"]["total"] == 1
    assert page["data"][0].type is StockType.adjust


def test_unknown_stock_type_returns_everything_unfiltered(db, world):
    page = list_stock_movements(db, stock_type="bogus", tenant_id=world["tenant"].id)
    assert page["meta"]["total"] == 3
