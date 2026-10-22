"""Bug reel : last_pull_at avancait a now_local() (horloge du serveur local
au moment du cycle) plutot qu'a la date du dernier enregistrement REELLEMENT
recu. Fenetre de perte silencieuse : si le cloud commite un changement entre
le moment ou le pull interroge et le moment ou ce cycle avance son curseur,
ce changement (updated_at anterieur au now_local() local) n'est jamais
redemande par un futur pull (filtre cote cloud : updated_at > since) - vu en
reel, un abonnement confirme cote cloud restait NULL indefiniment en local,
aucune erreur loguee. Ces tests verifient l'invariant : le curseur n'avance
jamais au-dela de ce qui a ete effectivement recu."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.Category import Category
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
def tenant(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    return t


def _run_pull(db, monkeypatch, records):
    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "category", "model": Category, "direction": "pull"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))

    def fake_http_post(url, json, headers, timeout=30):
        if url.endswith("/api/sync/push"):
            return _FakeResponse({"ok": True, "inserted": 0, "updated": 0, "skipped": 0})
        assert url.endswith("/api/sync/pull-batch")
        return _FakeResponse({"results": {
            "category": {"records": records, "has_more": False, "next_since": None},
        }})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)
    return lss.run_sync(db)


def test_cursor_advances_only_to_latest_record_seen(db, tenant, monkeypatch):
    old_ts = now_local() - timedelta(days=30)   # bien avant "maintenant"
    records = [
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "tenant_id": tenant.id, "name": "Cat A", "description": None,
            "created_at": old_ts.isoformat(), "updated_at": old_ts.isoformat(),
        },
    ]
    before = now_local()
    result = _run_pull(db, monkeypatch, records)
    assert result["ok"] is not False, result

    state = db.query(SyncState).filter_by(entity_type="category").first()
    assert state is not None
    # Le curseur doit refleter la date du DONNEE recue, pas l'horloge locale
    # du moment du cycle (qui serait tres proche de "before").
    assert abs((state.last_pull_at - old_ts).total_seconds()) < 2
    assert state.last_pull_at < before - timedelta(days=29)


def test_cursor_unchanged_when_nothing_received(db, tenant, monkeypatch):
    # Premier cycle : un enregistrement fixe le curseur a une date connue.
    old_ts = now_local() - timedelta(days=30)
    _run_pull(db, monkeypatch, [{
        "id": "22222222-2222-2222-2222-222222222222",
        "tenant_id": tenant.id, "name": "Cat B", "description": None,
        "created_at": old_ts.isoformat(), "updated_at": old_ts.isoformat(),
    }])
    state = db.query(SyncState).filter_by(entity_type="category").first()
    cursor_after_first = state.last_pull_at

    # Deuxieme cycle : rien de nouveau cote cloud (reponse vide). Le curseur
    # ne doit PAS bondir a l'horloge locale actuelle - sinon un changement
    # cloud commite juste apres ce cycle, avec un updated_at anterieur a
    # "maintenant" mais posterieur a cursor_after_first, serait manque pour
    # toujours par le prochain pull.
    result = _run_pull(db, monkeypatch, [])
    assert result["ok"] is not False, result

    db.refresh(state)
    assert state.last_pull_at == cursor_after_first
