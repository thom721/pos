"""SyncTombstone porte maintenant un warehouse_id, au meme titre que les
entites normales (test_sync_warehouse_scope.py) : pull-tombstones ne doit
renvoyer a une installation que les suppressions de SON depot (+ celles
partagees, warehouse_id NULL) — permissif plutot que fail-closed (voir
sync_pull_tombstones)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.requests import Request

import api.models  # noqa: F401
from api.database import Base
from api.models.Product import Product
from api.models.Category import Category
from api.models.SyncTombstone import SyncTombstone
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.routes.sync import TombstonePushRequest, sync_pull_tombstones, sync_push_tombstones


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


def _req(wh_id=None):
    headers = [(b"x-warehouse-id", wh_id.encode())] if wh_id else []
    return Request({"type": "http", "headers": headers})


def _claims(tenant_id):
    return {"tenant_id": tenant_id, "tenant_type": "shared"}


@pytest.fixture()
def world(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh_a = Warehouse(tenant_id=t.id, name="Dépôt A", is_active=True, is_default=True)
    wh_b = Warehouse(tenant_id=t.id, name="Dépôt B", is_active=True)
    cat = Category(tenant_id=t.id, name="Boissons")
    db.add_all([wh_a, wh_b, cat])
    db.commit()
    return {"tenant": t, "wh_a": wh_a, "wh_b": wh_b, "cat": cat}


def test_pull_tombstones_only_for_installation_warehouse(db, world):
    tenant, wh_a, wh_b = world["tenant"], world["wh_a"], world["wh_b"]
    db.add_all([
        SyncTombstone(entity_type="product", record_id="rec-a", tenant_id=tenant.id, warehouse_id=wh_a.id),
        SyncTombstone(entity_type="product", record_id="rec-b", tenant_id=tenant.id, warehouse_id=wh_b.id),
        SyncTombstone(entity_type="product", record_id="rec-shared", tenant_id=tenant.id, warehouse_id=None),
    ])
    db.commit()

    res = sync_pull_tombstones(request=_req(wh_a.id), entity_type="product",
                                since="1970-01-01T00:00:00", claims=_claims(tenant.id), db=db)
    ids = {r["record_id"] for r in res["records"]}
    assert ids == {"rec-a", "rec-shared"}


def test_pull_tombstones_without_header_returns_everything(db, world):
    """Pas d'en-tete (vieux serveur local non mis a jour) -> comportement
    inchange, aucun filtre — ne doit jamais regresser la propagation."""
    tenant, wh_a, wh_b = world["tenant"], world["wh_a"], world["wh_b"]
    db.add_all([
        SyncTombstone(entity_type="product", record_id="rec-a", tenant_id=tenant.id, warehouse_id=wh_a.id),
        SyncTombstone(entity_type="product", record_id="rec-b", tenant_id=tenant.id, warehouse_id=wh_b.id),
    ])
    db.commit()

    res = sync_pull_tombstones(request=_req(), entity_type="product",
                                since="1970-01-01T00:00:00", claims=_claims(tenant.id), db=db)
    ids = {r["record_id"] for r in res["records"]}
    assert ids == {"rec-a", "rec-b"}


def test_push_tombstones_resolves_warehouse_from_still_existing_row(db, world):
    """La ligne existe encore cote cloud au moment du push — son
    warehouse_id reel doit etre utilise, pas besoin que le serveur local
    le precise."""
    tenant, wh_a, cat = world["tenant"], world["wh_a"], world["cat"]
    prod = Product(tenant_id=tenant.id, warehouse_id=wh_a.id, category_id=cat.id,
                    name="Produit A", sale_price=10)
    db.add(prod)
    db.commit()
    prod_id = prod.id

    sync_push_tombstones(
        body=TombstonePushRequest(entity_type="product", record_ids=[prod_id]),
        claims=_claims(tenant.id), db=db,
    )

    tombstone = db.query(SyncTombstone).filter_by(entity_type="product", record_id=prod_id).first()
    assert tombstone is not None
    assert tombstone.warehouse_id == wh_a.id


def test_push_tombstones_falls_back_to_declared_warehouse_when_row_already_gone(db, world):
    """La ligne a deja disparu cote cloud (ex: supprimee par un autre
    serveur local du meme tenant) — on ne peut plus lire son warehouse_id
    reel, donc on retombe sur celui declare par le serveur qui pousse."""
    tenant, wh_a = world["tenant"], world["wh_a"]

    sync_push_tombstones(
        body=TombstonePushRequest(entity_type="product", record_ids=["ghost-id"],
                                   warehouse_ids={"ghost-id": wh_a.id}),
        claims=_claims(tenant.id), db=db,
    )

    tombstone = db.query(SyncTombstone).filter_by(entity_type="product", record_id="ghost-id").first()
    assert tombstone is not None
    assert tombstone.warehouse_id == wh_a.id
