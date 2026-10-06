"""Rabais par dépôt : un rabais lié à un dépôt n'est utilisable que dans ce dépôt.
warehouse_id NULL = rabais disponible dans tous les dépôts du tenant.
"""
from decimal import Decimal

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.requests import Request

import api.models  # noqa: F401
from api.database import Base
from api.models.Discount import Discount, DiscountScope, DiscountType
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.routes.sync import PullBatchRequest, sync_pull_batch
from api.services.discount_service import DiscountService, resolve_discount


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
    db.add_all([wh_a, wh_b])
    db.flush()
    only_a = Discount(tenant_id=t.id, name="Rabais A", type=DiscountType.percentage, value=Decimal("5"),
                      scope=DiscountScope.receipt, warehouse_id=wh_a.id)
    everywhere = Discount(tenant_id=t.id, name="Rabais tous", type=DiscountType.percentage, value=Decimal("1"),
                          scope=DiscountScope.receipt, warehouse_id=None)
    db.add_all([only_a, everywhere])
    db.commit()
    return {"tenant": t, "wh_a": wh_a, "wh_b": wh_b, "only_a": only_a, "everywhere": everywhere}


def _req(wh_id=None):
    headers = [(b"x-warehouse-id", wh_id.encode())] if wh_id else []
    return Request({"type": "http", "headers": headers})


def test_discount_refused_in_other_warehouse(db, world):
    with pytest.raises(HTTPException) as exc:
        resolve_discount(db, world["only_a"].id, 0, {DiscountScope.receipt},
                         Decimal("100"), warehouse_id=world["wh_b"].id)
    assert exc.value.status_code == 400


def test_discount_accepted_in_its_warehouse(db, world):
    amount, disc_id = resolve_discount(db, world["only_a"].id, 0, {DiscountScope.receipt},
                                       Decimal("100"), warehouse_id=world["wh_a"].id)
    assert disc_id == world["only_a"].id
    assert amount == Decimal("5")


def test_all_warehouses_discount_accepted_anywhere(db, world):
    _, disc_id = resolve_discount(db, world["everywhere"].id, 0, {DiscountScope.receipt},
                                  Decimal("100"), warehouse_id=world["wh_b"].id)
    assert disc_id == world["everywhere"].id


def test_list_filtered_by_warehouse(db, world):
    names = {d.name for d in DiscountService(db, tenant_id=world["tenant"].id).list(warehouse_id=world["wh_b"].id)}
    assert names == {"Rabais tous"}
    names_a = {d.name for d in DiscountService(db, tenant_id=world["tenant"].id).list(warehouse_id=world["wh_a"].id)}
    assert names_a == {"Rabais A", "Rabais tous"}


def test_create_rejects_warehouse_of_other_tenant(db, world):
    other = Tenant(business_name="X", owner_email="x@x.com", slug="x")
    db.add(other)
    db.flush()
    foreign = Warehouse(tenant_id=other.id, name="Autre", is_active=True)
    db.add(foreign)
    db.commit()
    with pytest.raises(HTTPException):
        DiscountService(db, tenant_id=world["tenant"].id).create(
            {"name": "Nouveau", "type": "percentage", "value": 2, "scope": "receipt",
             "warehouse_id": foreign.id}
        )


def test_sync_pull_discounts_scoped_and_global(db, world):
    body = PullBatchRequest(cursors={"discount": "1970-01-01T00:00:00"})
    res = sync_pull_batch(body=body, request=_req(world["wh_b"].id),
                          claims={"tenant_id": world["tenant"].id, "tenant_type": "shared"}, db=db)
    names = {r["name"] for r in res["results"]["discount"]["records"]}
    assert names == {"Rabais tous"}
