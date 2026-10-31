"""Bug reel : aucune suppression ne pouvait jamais se propager entre cloud
et local - le pull/push normal filtre sur updated_at, une ligne supprimee
n'a plus de ligne a filtrer. Constate en prod (Maranatha Lessive) : un
admin a supprime 3 paliers de prix (ProductPriceTier) via le dashboard
cloud, le serveur local les a gardes indefiniment, aucune trace nulle
part. Corrige via un mecanisme de "tombstones" (sync_tombstones) echange
en parallele du push/pull normal — voir tombstone_service.py et les
blocs "PUSH TOMBSTONES"/"PULL TOMBSTONES" dans run_sync()."""
from datetime import timedelta

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
from api.models.SyncState import SyncState
from api.models.SyncTombstone import SyncTombstone
from api.services import price_tier_service
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
    Session = sessionmaker(bind=engine)
    session = Session()
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
    p = Product(name="CAISSE COCA 20 0Z", category_id=cat.id, sale_price=2075, tenant_id=t.id)
    db.add(p)
    db.commit()
    return {"tenant": t, "wh": wh, "product": p}


class _Tier:
    def __init__(self, min_quantity, price):
        self.min_quantity = min_quantity
        self.price = price


def test_removing_tiers_via_set_tiers_creates_one_tombstone_per_row(db, world):
    """set_tiers() remplace tout le lot (delete-then-recreate, meme pour les
    seuils inchanges) — chaque ligne supprimee doit laisser SA PROPRE
    tombstone, pas une seule tombstone globale pour l'operation."""
    tid, p, wh = world["tenant"].id, world["product"], world["wh"]

    price_tier_service.set_tiers(db, tid, p.id, wh.id, [
        _Tier(3, 2050), _Tier(10, 2050), _Tier(50, 2040), _Tier(100, 2025),
    ])
    db.commit()
    created = db.query(ProductPriceTier).filter_by(product_id=p.id).all()
    assert len(created) == 4
    original_ids = {str(r.id) for r in created}

    # L'admin ne resoumet qu'un seul palier — les 4 lignes d'origine
    # (set_tiers recree tout le lot) doivent etre tombstonees individuellement,
    # pas juste disparaitre silencieusement.
    price_tier_service.set_tiers(db, tid, p.id, wh.id, [_Tier(3, 2050)])
    db.commit()

    remaining = db.query(ProductPriceTier).filter_by(product_id=p.id).all()
    assert len(remaining) == 1
    assert float(remaining[0].min_quantity) == 3
    assert str(remaining[0].id) not in original_ids, "set_tiers recree une ligne neuve, pas un update"

    tombstones = db.query(SyncTombstone).filter_by(entity_type="product_price_tier").all()
    assert len(tombstones) == 4, "une tombstone par ligne supprimee, pas une seule globale"
    assert {t.record_id for t in tombstones} == original_ids


def test_pull_tombstones_deletes_stale_local_rows(db, world, monkeypatch):
    """Reproduit l'incident reel cote local : le cloud a deja supprime 3
    paliers (tombstones existent la-bas), le serveur local les a encore —
    un cycle de pull de tombstones doit les faire disparaitre ici aussi."""
    tid, p, wh = world["tenant"].id, world["product"], world["wh"]

    # Etat local AVANT correction : 4 paliers, comme vu en prod sur
    # Maranatha Lessive (le cloud, lui, n'en a plus qu'un).
    tiers = []
    for qty, price in [(3, 2050), (10, 2050), (50, 2025), (100, 2040)]:
        t = ProductPriceTier(tenant_id=tid, product_id=p.id, warehouse_id=wh.id,
                              min_quantity=qty, price=price)
        db.add(t)
        tiers.append(t)
    db.commit()
    stale_ids = [t.id for t in tiers if float(t.min_quantity) != 3]
    assert len(stale_ids) == 3

    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "product_price_tier", "model": ProductPriceTier, "direction": "both"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))
    monkeypatch.setattr(lss, "_installer_warehouse_id", lambda: "")

    def fake_http_post(url, json, headers, timeout=30):
        if url.endswith("/api/sync/pull-batch"):
            return _FakeResponse({"results": {}})
        if url.endswith("/api/sync/push-tombstones"):
            return _FakeResponse({"ok": True, "deleted": 0})
        return _FakeResponse({"ok": True})

    def fake_http_get(url, params, headers, timeout=30):
        if url.endswith("/api/sync/pull-tombstones"):
            # Le cloud a bien les 3 tombstones correspondant aux paliers
            # supprimes la-bas — c'est ce qu'un pull doit ramener.
            now_iso = now_local().isoformat()
            return _FakeResponse({
                "entity_type": "product_price_tier",
                "records": [{"record_id": rid, "updated_at": now_iso} for rid in stale_ids],
            })
        # pull normal (/api/sync/pull) — rien de nouveau a tirer.
        return _FakeResponse({"records": [], "has_more": False, "next_since": None})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)
    monkeypatch.setattr(lss, "_http_get", fake_http_get)

    lss.run_sync(db)

    remaining = db.query(ProductPriceTier).filter_by(product_id=p.id).all()
    assert len(remaining) == 1, (
        "les 3 paliers tombstones cote cloud doivent avoir ete supprimes "
        "localement par le cycle de pull de tombstones"
    )
    assert float(remaining[0].min_quantity) == 3
