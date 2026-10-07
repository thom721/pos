"""Une installation locale ne reçoit et n'envoie que les lignes de SON dépôt.

Le dépôt vient de l'en-tête X-Warehouse-Id (installer_warehouse_id du serveur
local), vérifié contre le tenant du token. Les entités propres à un dépôt
(produits, ventes, lignes de vente…) sont filtrées ; les entités partagées
(catégories, fournisseurs, clients, remises) ne le sont pas.
"""
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.requests import Request

import api.models  # noqa: F401
from api.database import Base
from api.models.Category import Category
from api.models.Product import Product
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.routes.sync import PullBatchRequest, PushRequest, sync_pull, sync_pull_batch, sync_push


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
    db.flush()
    prod_a = Product(tenant_id=t.id, warehouse_id=wh_a.id, category_id=cat.id, name="A", sale_price=10)
    prod_b = Product(tenant_id=t.id, warehouse_id=wh_b.id, category_id=cat.id, name="B", sale_price=10)
    db.add_all([prod_a, prod_b])
    db.commit()
    return {"tenant": t, "wh_a": wh_a, "wh_b": wh_b, "cat": cat, "prod_a": prod_a, "prod_b": prod_b}


def test_pull_products_only_for_installation_warehouse(db, world):
    res = sync_pull(request=_req(world["wh_a"].id), entity_type="product",
                    since="1970-01-01T00:00:00", claims=_claims(world["tenant"].id), db=db)
    ids = {r["id"] for r in res["records"]}
    assert world["prod_a"].id in ids
    assert world["prod_b"].id not in ids


def test_pull_without_warehouse_header_returns_no_warehouse_data(db, world):
    res = sync_pull(request=_req(), entity_type="product",
                    since="1970-01-01T00:00:00", claims=_claims(world["tenant"].id), db=db)
    assert res["records"] == []


def test_pull_product_serializes_is_service(db, world):
    """is_service (colonne ajoutée pour le type "service") doit traverser
    sync_pull sans mapping explicite — _row_to_dict introspecte toutes les
    colonnes du modèle, aucun champ whitelist à maintenir côté sync."""
    world["prod_a"].is_service = True
    db.commit()

    res = sync_pull(request=_req(world["wh_a"].id), entity_type="product",
                    since="1970-01-01T00:00:00", claims=_claims(world["tenant"].id), db=db)
    by_id = {r["id"]: r for r in res["records"]}
    assert by_id[world["prod_a"].id]["is_service"] is True


def test_pull_shared_entities_still_returned(db, world):
    res = sync_pull(request=_req(world["wh_a"].id), entity_type="category",
                    since="1970-01-01T00:00:00", claims=_claims(world["tenant"].id), db=db)
    assert world["cat"].id in {r["id"] for r in res["records"]}


def test_pull_rejects_warehouse_of_another_tenant(db, world):
    other = Tenant(business_name="Autre", owner_email="x@x.com", slug="autre")
    db.add(other)
    db.flush()
    foreign = Warehouse(tenant_id=other.id, name="Autre dépôt", is_active=True)
    db.add(foreign)
    db.commit()
    with pytest.raises(HTTPException) as exc:
        sync_pull(request=_req(foreign.id), entity_type="product",
                  since="1970-01-01T00:00:00", claims=_claims(world["tenant"].id), db=db)
    assert exc.value.status_code == 403


def test_pull_batch_scoped_to_installation_warehouse(db, world):
    body = PullBatchRequest(cursors={"product": "1970-01-01T00:00:00"})
    res = sync_pull_batch(body=body, request=_req(world["wh_b"].id),
                          claims=_claims(world["tenant"].id), db=db)
    ids = {r["id"] for r in res["results"]["product"]["records"]}
    assert ids == {world["prod_b"].id}


def test_push_rejects_rows_of_another_warehouse(db, world):
    records = [
        {"id": "11111111-1111-1111-1111-111111111111", "warehouse_id": world["wh_a"].id,
         "category_id": world["cat"].id, "name": "Ok", "sale_price": 5},
        {"id": "22222222-2222-2222-2222-222222222222", "warehouse_id": world["wh_b"].id,
         "category_id": world["cat"].id, "name": "Pas ici", "sale_price": 5},
    ]
    res = sync_push(body=PushRequest(entity_type="product", records=records),
                    request=_req(world["wh_a"].id), claims=_claims(world["tenant"].id), db=db)
    assert res["inserted"] == 1
    assert db.get(Product, "11111111-1111-1111-1111-111111111111") is not None
    assert db.get(Product, "22222222-2222-2222-2222-222222222222") is None
