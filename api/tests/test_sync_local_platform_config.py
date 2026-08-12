"""Bug corrigé : un poste local n'a jamais de ligne PlatformConfig au départ
(_ensure_cloud_admin ne la crée que côté cloud — elle skip explicitement dès
que CLOUD_SYNC_URL est configuré, ce qui est toujours le cas sur un poste
local). run_sync() ne mettait à jour la config publique (prix, essai
entrepôt...) QUE si une ligne locale existait déjà — donc sur un poste
local fraîchement installé, cette synchro ne faisait jamais rien, et
get_billing_config() (api/routes/billing.py) retombait indéfiniment sur ses
valeurs de repli codées en dur (500 HTG etc.), quels que soient les prix
réellement configurés côté admin cloud."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.PlatformConfig import PlatformConfig
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


def _run_sync_with_public_config(db, monkeypatch, pub_config: dict):
    monkeypatch.setattr(lss, "SYNC_ENTITIES", [])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))

    def fake_http_get(url, params, headers, timeout=30):
        if url.endswith("/api/sync/tenant-billing"):
            return _FakeResponse({})
        if url.endswith("/api/sync/public-platform-config"):
            return _FakeResponse(pub_config)
        raise AssertionError(f"unexpected GET {url}")

    monkeypatch.setattr(lss, "_http_get", fake_http_get)
    return lss.run_sync(db)


def test_public_config_creates_local_row_when_missing(db, monkeypatch):
    assert db.query(PlatformConfig).first() is None

    _run_sync_with_public_config(db, monkeypatch, {
        "price_per_extra_depot_htg": 750.0,
        "price_per_extra_depot_usd": 6.0,
        "entrepot_trial_days": 45,
        "entrepot_trial_all": True,
    })

    local_cfg = db.query(PlatformConfig).first()
    assert local_cfg is not None
    assert float(local_cfg.price_per_extra_depot_htg) == 750.0
    assert float(local_cfg.price_per_extra_depot_usd) == 6.0
    assert local_cfg.entrepot_trial_days == 45
    assert local_cfg.entrepot_trial_all is True


def test_public_config_updates_existing_local_row(db, monkeypatch):
    existing = PlatformConfig(price_per_extra_depot_htg=500.0, entrepot_trial_days=30)
    db.add(existing)
    db.commit()

    _run_sync_with_public_config(db, monkeypatch, {
        "price_per_extra_depot_htg": 900.0,
        "entrepot_trial_days": 60,
    })

    rows = db.query(PlatformConfig).all()
    assert len(rows) == 1
    assert float(rows[0].price_per_extra_depot_htg) == 900.0
    assert rows[0].entrepot_trial_days == 60
