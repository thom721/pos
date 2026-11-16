"""Bug reel (incident Maranatha Lessive, 2026-11-16) : run_sync() traitait
toutes les entites du cycle de pull dans UNE SEULE session non validee,
avec un seul db.commit() a la toute fin de la boucle. Si une entite PLUS
LOIN dans SYNC_ENTITIES echouait a CHAQUE cycle (ex: FK vers une ligne
jamais synchronisee), son db.rollback() effacait AUSSI tout ce que les
entites precedentes avaient deja applique avec succes DANS CE MEME cycle
— y compris leur propre curseur last_pull_at, lui aussi annule. Resultat :
une mise a jour reussie (ex: un palier de prix modifie sur le cloud)
etait rejouee puis effacee a l'identique a chaque cycle, indefiniment,
SANS JAMAIS laisser de last_error sur SA PROPRE entite — l'erreur venait
d'une autre, plus loin dans la liste. Corrige en committant par entite."""
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
    p = Product(name="JUGOO 20 OZ", category_id=cat.id, sale_price=1400, tenant_id=t.id)
    db.add(p)
    db.flush()
    # Palier local PERIME (prix encore a l'ancienne valeur) — meme id different
    # de celui que le cloud recreera au prochain set_tiers() (delete-then-
    # recreate, voir price_tier_service.py).
    old_tier = ProductPriceTier(tenant_id=t.id, product_id=p.id, warehouse_id=wh.id,
                                 min_quantity=3, price=1700)
    db.add(old_tier)
    db.commit()
    return {"tenant": t, "wh": wh, "cat": cat, "product": p, "old_tier": old_tier}


def test_later_entity_failure_does_not_erase_earlier_entity_success(db, world, monkeypatch):
    tid, wh, p = world["tenant"].id, world["wh"], world["product"]

    # SYNC_ENTITIES reduit a deux entites : product_price_tier (reussit),
    # puis category (echoue a CHAQUE cycle, comme un vrai blocage FK en
    # production).
    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "product_price_tier", "model": ProductPriceTier, "direction": "pull"},
        {"type": "category", "model": Category, "direction": "pull"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))
    monkeypatch.setattr(lss, "_installer_warehouse_id", lambda: "")

    new_updated_at = (now_local() + timedelta(minutes=1)).isoformat()

    def fake_http_post(url, json, headers, timeout=30):
        if url.endswith("/api/sync/pull-batch"):
            return _FakeResponse({"results": {}})  # repli sur pull individuel
        return _FakeResponse({"ok": True})

    def fake_http_get(url, params, headers, timeout=30):
        if url.endswith("/api/sync/pull-tombstones"):
            return _FakeResponse({"entity_type": params["entity_type"], "records": []})
        if url.endswith("/api/sync/pull"):
            if params["entity_type"] == "product_price_tier":
                return _FakeResponse({
                    "records": [{
                        "id": "new-cloud-tier-id",
                        "tenant_id": tid,
                        "product_id": p.id,
                        "warehouse_id": wh.id,
                        "min_quantity": 3,
                        "price": 1400,
                        "updated_at": new_updated_at,
                    }],
                    "has_more": False, "next_since": None,
                })
            if params["entity_type"] == "category":
                # Panne persistante sur une AUTRE entite — meme a chaque
                # cycle, comme un vrai blocage FK en prod.
                raise RuntimeError("boom cote category — panne persistante")
        return _FakeResponse({"records": [], "has_more": False, "next_since": None})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)
    monkeypatch.setattr(lss, "_http_get", fake_http_get)

    summary = lss.run_sync(db)

    db.refresh(world["old_tier"])
    assert float(world["old_tier"].price) == 1400, (
        "la mise a jour du palier (reussie) ne doit PAS etre effacee par "
        "l'echec d'une AUTRE entite plus loin dans le cycle"
    )

    tier_state = db.query(SyncState).filter_by(entity_type="product_price_tier").first()
    assert tier_state.last_error is None, (
        "product_price_tier a reussi — son propre last_error ne doit "
        "jamais porter la trace de l'echec d'une autre entite"
    )
    assert any("category" in e for e in summary["errors"])
