"""Decision explicite (demande utilisateur, 2026-11) : le cloud est la
SEULE source de verite pour les paliers de prix. Une ligne locale qui
n'existe pas cote cloud — meme si elle n'a JAMAIS ete connue la-bas (creee
directement en local, ex: SQL direct) — doit etre supprimee au prochain
cycle de synchro, pas seulement celles explicitement tombstonees (le pull
incremental normal ne peut jamais detecter un orphelin qu'il n'a jamais
vu passer). Voir _reconcile_cloud_source_of_truth dans local_sync_service.py."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.Category import Category
from api.models.Product import Product
from api.models.ProductPriceTier import ProductPriceTier
import api.services.local_sync_service as lss


class _FakeResponse:
    def __init__(self, data):
        self._data = data

    def json(self):
        return self._data


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
    wh = Warehouse(tenant_id=t.id, name="Maranatha Lessive", is_active=True, is_default=True)
    cat = Category(name="Boissons", tenant_id=t.id)
    db.add_all([wh, cat])
    db.flush()
    p1 = Product(name="CAISSE FIESTA 20 OZ", category_id=cat.id, sale_price=1400, tenant_id=t.id)
    p2 = Product(name="CAISSE PRORADE 20 OZ", category_id=cat.id, sale_price=1925, tenant_id=t.id)
    db.add_all([p1, p2])
    db.flush()
    # p1 : tier connu du cloud (doit survivre). p2 : tier cree directement
    # en local, jamais connu du cloud (doit etre supprime).
    kept = ProductPriceTier(tenant_id=t.id, product_id=p1.id, warehouse_id=wh.id,
                             min_quantity=3, price=1400)
    orphan = ProductPriceTier(tenant_id=t.id, product_id=p2.id, warehouse_id=wh.id,
                               min_quantity=3, price=1925)
    db.add_all([kept, orphan])
    db.commit()
    return {"tenant": t, "wh": wh, "p1": p1, "p2": p2, "kept": kept, "orphan": orphan}


def _setup_common(monkeypatch, world, cloud_records):
    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "product_price_tier", "model": ProductPriceTier, "direction": "pull"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))

    def fake_http_post(url, json, headers, timeout=30):
        return _FakeResponse({"results": {}})  # repli sur pull individuel

    def fake_http_get(url, params, headers, timeout=30):
        if url.endswith("/api/sync/pull-tombstones"):
            return _FakeResponse({"entity_type": params["entity_type"], "records": []})
        if url.endswith("/api/sync/pull"):
            return _FakeResponse({"records": cloud_records, "has_more": False, "next_since": None})
        return _FakeResponse({"records": [], "has_more": False, "next_since": None})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)
    monkeypatch.setattr(lss, "_http_get", fake_http_get)


def test_local_only_tier_never_known_to_cloud_gets_deleted(db, world, monkeypatch):
    tid, wh, p1 = world["tenant"].id, world["wh"], world["p1"]
    now_iso = now_local().isoformat()
    # Le cloud ne connait QUE le palier de p1 — celui de p2 (orphan) n'a
    # jamais existe la-bas.
    cloud_records = [{
        "id": "cloud-tier-id", "tenant_id": tid, "product_id": p1.id,
        "warehouse_id": wh.id, "min_quantity": 3, "price": 1400,
        "updated_at": now_iso,
    }]
    _setup_common(monkeypatch, world, cloud_records)
    monkeypatch.setattr(lss, "_installer_warehouse_id", lambda: wh.id)

    lss.run_sync(db)

    remaining = db.query(ProductPriceTier).filter_by(warehouse_id=wh.id).all()
    assert len(remaining) == 1
    assert remaining[0].product_id == p1.id, "le palier connu du cloud doit survivre"


def test_reconciliation_skipped_without_configured_warehouse(db, world, monkeypatch):
    """Garde-fou : sans depot configure, le cloud ne renverrait rien
    (fail-closed cote cloud) — ne JAMAIS tout supprimer localement dans ce cas."""
    wh = world["wh"]
    _setup_common(monkeypatch, world, cloud_records=[])
    monkeypatch.setattr(lss, "_installer_warehouse_id", lambda: "")

    lss.run_sync(db)

    remaining = db.query(ProductPriceTier).filter_by(warehouse_id=wh.id).all()
    assert len(remaining) == 2, "aucune suppression sans depot configure"
