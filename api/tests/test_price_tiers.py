"""Paliers de prix par produit et par dépôt."""
from decimal import Decimal

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Category import Category
from api.models.Product import Product
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.routes.sync import _MODEL_MAP
from api.services import price_tier_service as svc


class _T:
    def __init__(self, q, p):
        self.min_quantity = q
        self.price = p


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
    wh_a = Warehouse(tenant_id=t.id, name="Maranatha", is_active=True, is_default=True)
    wh_b = Warehouse(tenant_id=t.id, name="NES", is_active=True)
    cat = Category(tenant_id=t.id, name="Boissons")
    db.add_all([wh_a, wh_b, cat])
    db.flush()
    prod = Product(tenant_id=t.id, warehouse_id=wh_a.id, category_id=cat.id, name="Fiesta", sale_price=1800)
    db.add(prod)
    db.commit()
    return {"tenant": t, "wh_a": wh_a, "wh_b": wh_b, "prod": prod}


def test_no_tier_returns_none(db, world):
    assert svc.tier_price(db, world["prod"].id, world["wh_a"].id, 5) is None


def test_highest_reached_tier_applies(db, world):
    svc.set_tiers(db, world["tenant"].id, world["prod"].id, world["wh_a"].id, [
        _T(3, 1700), _T(12, 1600), _T(24, 1550),
    ])
    p, a = world["prod"].id, world["wh_a"].id
    assert svc.tier_price(db, p, a, 1) is None          # sous le premier seuil : prix normal
    assert svc.tier_price(db, p, a, 3) == Decimal("1700")
    assert svc.tier_price(db, p, a, 11) == Decimal("1700")
    assert svc.tier_price(db, p, a, 12) == Decimal("1600")
    assert svc.tier_price(db, p, a, 100) == Decimal("1550")


def test_tiers_are_per_warehouse(db, world):
    svc.set_tiers(db, world["tenant"].id, world["prod"].id, world["wh_a"].id, [_T(3, 1700)])
    assert svc.tier_price(db, world["prod"].id, world["wh_b"].id, 5) is None


def test_price_must_not_increase_with_quantity(db, world):
    with pytest.raises(HTTPException) as exc:
        svc.set_tiers(db, world["tenant"].id, world["prod"].id, world["wh_a"].id, [_T(3, 1600), _T(12, 1700)])
    assert exc.value.status_code == 400


def test_duplicate_threshold_refused(db, world):
    with pytest.raises(HTTPException):
        svc.set_tiers(db, world["tenant"].id, world["prod"].id, world["wh_a"].id, [_T(3, 1700), _T(3, 1650)])


def test_set_replaces_previous_tiers(db, world):
    svc.set_tiers(db, world["tenant"].id, world["prod"].id, world["wh_a"].id, [_T(3, 1700), _T(12, 1600)])
    svc.set_tiers(db, world["tenant"].id, world["prod"].id, world["wh_a"].id, [_T(6, 1650)])
    rows = svc.list_tiers(db, world["tenant"].id, world["prod"].id, world["wh_a"].id)
    assert [(float(r.min_quantity), float(r.price)) for r in rows] == [(6.0, 1650.0)]


def test_tier_entity_is_synced():
    assert "product_price_tier" in _MODEL_MAP


def test_list_all_tiers_only_for_warehouse(db, world):
    svc.set_tiers(db, world["tenant"].id, world["prod"].id, world["wh_a"].id, [_T(3, 1700)])
    svc.set_tiers(db, world["tenant"].id, world["prod"].id, world["wh_b"].id, [_T(3, 1650)])
    rows = svc.list_all_tiers(db, world["tenant"].id, world["wh_a"].id)
    assert [(float(r.min_quantity), float(r.price)) for r in rows] == [(3.0, 1700.0)]
