"""Bug reel : quand le cloud repond a un push avec skipped > 0 (une ligne a
echoue a l'insertion/mise a jour cote serveur, ex: contrainte violee), le
serveur local ignorait completement ce compteur et faisait quand meme
avancer last_push_at jusqu'a cycle_start. La ligne skippee sortait alors
pour toujours de la fenetre "updated_at > last_push_at" et n'etait plus
jamais retentee - perdue en silence, sans aucune trace ni cote local ni
cote cloud visible pour l'operateur. Constate en prod (Maranatha Lessive) :
deux ventes payees (VNT-00271, VNT-00335) jamais arrivees au cloud, aucune
erreur nulle part.

Corrige : si skipped > 0, le curseur n'avance pas pour ce cycle - tout le
lot est retente au prochain cycle, et un message d'erreur reste visible
dans SyncState.last_error / summary["errors"]."""
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
    cat = Category(tenant_id=t.id, name="Cat")
    db.add_all([wh, cat])
    db.flush()
    p = Product(tenant_id=t.id, warehouse_id=wh.id, category_id=cat.id,
                name="Sachet", sale_price=10)
    db.add(p)
    db.commit()
    return {"tenant": t, "wh": wh, "cat": cat, "product": p}


def test_push_cursor_does_not_advance_when_cloud_skips_a_record(db, world, monkeypatch):
    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "product", "model": Product, "direction": "push"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))
    monkeypatch.setattr(lss, "_installer_warehouse_id", lambda: world["wh"].id)

    # Curseur deja avance une fois dans le passe (simule un historique normal).
    state = SyncState(entity_type="product", last_push_at=now_local() - timedelta(days=1))
    db.add(state)
    db.commit()

    def fake_http_post(url, json, headers, timeout=30):
        assert url.endswith("/api/sync/push")
        # Le cloud a rejete la ligne (ex: contrainte violee) - skipped=1,
        # mais la requete HTTP elle-meme reussit (200 OK), rien ne leve.
        return _FakeResponse({"ok": True, "inserted": 0, "updated": 0, "skipped": 1})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)

    result = lss.run_sync(db)

    assert result["errors"], "un skipped > 0 doit etre remonte dans les erreurs du cycle"

    db.refresh(state)
    assert state.last_push_at < now_local() - timedelta(hours=1), (
        "le curseur ne doit pas avancer quand le cloud a rejete une ligne — "
        "sinon elle sort pour toujours de la fenetre de push et est perdue en silence"
    )
    assert state.last_error, "last_error doit rester visible pour l'operateur"


def test_push_cursor_advances_normally_when_nothing_skipped(db, world, monkeypatch):
    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "product", "model": Product, "direction": "push"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))
    monkeypatch.setattr(lss, "_installer_warehouse_id", lambda: world["wh"].id)

    state = SyncState(entity_type="product", last_push_at=now_local() - timedelta(days=1))
    db.add(state)
    db.commit()

    def fake_http_post(url, json, headers, timeout=30):
        return _FakeResponse({"ok": True, "inserted": 1, "updated": 0, "skipped": 0})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)

    result = lss.run_sync(db)

    assert not result["errors"], result
    db.refresh(state)
    assert state.last_push_at > now_local() - timedelta(minutes=1), (
        "le comportement normal (rien de skippe) ne doit pas regresser"
    )
