"""Bug corrigé : _run_sync_inner catchait l'exception d'une entité en échec
(ex: IntegrityError sur un component_product_id orphelin, ou un palier de
prix en double) mais n'appelait jamais db.rollback() — la session restait
"transaction rolled back" pour le reste du cycle, cassant en cascade TOUTES
les entités suivantes de SYNC_ENTITIES, à chaque cycle, indéfiniment (vu en
prod sur Maranatha Lessive les 14 et 15/10, deux causes différentes, même
symptôme). Ce test prouve qu'une entité en échec n'empêche plus les
suivantes de se synchroniser normalement.
"""
import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.Category import Category
from api.models.Product import Product
from api.models.Discount import Discount
import api.services.local_sync_service as lss


class _FakeResponse:
    def __init__(self, data):
        self._data = data

    def json(self):
        return self._data


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")

    # SQLite n'applique pas les FK par défaut — l'app réelle l'active
    # explicitement (voir api/database.py), sans quoi ce test ne pourrait
    # jamais reproduire l'IntegrityError observée en prod (MySQL, lui,
    # applique toujours ses contraintes).
    @event.listens_for(engine, "connect")
    def _enable_fk(dbapi_conn, _):
        dbapi_conn.execute("PRAGMA foreign_keys=ON")

    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def world(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Depot", is_active=True, is_default=True)
    cat = Category(tenant_id=t.id, name="Boissons")
    db.add_all([wh, cat])
    db.flush()
    # Produit déjà présent localement — va recevoir une MISE À JOUR (pas un
    # insert) pointant vers un composant qui n'existe pas localement, pour
    # reproduire exactement le mécanisme observé en prod : setattr() différé,
    # aucune protection try/except sur ce chemin (contrairement à l'insert).
    existing_product = Product(
        tenant_id=t.id, warehouse_id=wh.id, category_id=cat.id,
        name="Sachet", sale_price=100,
    )
    db.add(existing_product)
    db.commit()
    return {"tenant": t, "wh": wh, "cat": cat, "product": existing_product}


def test_discount_syncs_despite_earlier_product_failure(db, world, monkeypatch):
    # product (reçoit la mise à jour cassée) -> category (c'est là que le
    # flush différé explose réellement, exactement comme en prod) -> discount
    # (la vraie preuve : doit quand même passer si la session a été
    # correctement réinitialisée après l'échec de category).
    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "product",  "model": Product,  "direction": "pull"},
        {"type": "category", "model": Category, "direction": "pull"},
        {"type": "discount", "model": Discount, "direction": "pull"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))
    monkeypatch.setattr(lss, "_installer_warehouse_id", lambda: world["wh"].id)

    bad_product_update = {
        "id": world["product"].id,
        "tenant_id": world["tenant"].id,
        "warehouse_id": world["wh"].id,
        "category_id": world["cat"].id,
        "name": "Sachet",
        "sale_price": 100,
        # Composant inexistant localement — FK violation différée au
        # prochain flush (déclenché par le category.pull qui suit), pas
        # catturée au moment du setattr() lui-même.
        "component_product_id": "00000000-0000-0000-0000-000000000000",
        "component_quantity": 1.0,
        "created_at": "2026-10-07T10:37:34",
        "updated_at": "2026-10-16T09:00:00",
    }
    new_category = {
        "id": "11111111-1111-1111-1111-111111111111",
        "tenant_id": world["tenant"].id,
        "name": "Nouvelle Categorie",
        "description": None,
        "created_at": "2026-10-16T09:00:00",
        "updated_at": "2026-10-16T09:00:00",
    }

    new_discount = {
        "id": "22222222-2222-2222-2222-222222222222",
        "tenant_id": world["tenant"].id,
        "warehouse_id": None,
        "name": "Solde",
        "type": "fixed",
        "value": 10,
        "scope": "both",
        "is_automatic": False,
        "is_active": True,
        "schedule_days": None,
        "schedule_start": None,
        "schedule_end": None,
        "min_quantity": None,
        "product_ids": None,
        "created_at": "2026-10-16T09:00:00",
        "updated_at": "2026-10-16T09:00:00",
    }

    def fake_http_post(url, json, headers, timeout=30):
        assert url.endswith("/api/sync/pull-batch")
        return _FakeResponse({"results": {
            "product":  {"records": [bad_product_update], "has_more": False, "next_since": None},
            "category": {"records": [new_category],       "has_more": False, "next_since": None},
            "discount": {"records": [new_discount],        "has_more": False, "next_since": None},
        }})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)

    result = lss.run_sync(db)

    # Une entite a bien echoue (le flush differe du mauvais component_product_id
    # explose au moment de traiter "category", pas "product" lui-meme).
    assert result["errors"], result

    # La vraie preuve du correctif : l'entite qui suit celle qui a absorbe
    # l'echec se synchronise quand meme normalement, parce que db.rollback()
    # a remis la session dans un etat utilisable. Sans le correctif, cette
    # assertion echoue (la discount n'est jamais appliquee).
    disc = db.get(Discount, "22222222-2222-2222-2222-222222222222")
    assert disc is not None, f"discount jamais appliquee — cascade non corrigee. errors={result['errors']}"
    assert disc.name == "Solde"
