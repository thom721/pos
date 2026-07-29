"""Bug corrigé : PosRegister.__table_args__ déclare UniqueConstraint('tenant_id',
'device_id') depuis toujours, mais _sync_schema_from_models() n'ajoute que des
colonnes — jamais de contraintes — donc une table pos_registers déjà existante
en production n'a jamais vraiment cette contrainte posée. Deux registres ont pu
s'accumuler pour le même (tenant_id, device_id) côté cloud (ex: changement de
dépôt actif sur le même poste). Une installation locale FRAÎCHE (dont la table
est créée via create_all() et respecte donc la contrainte dès le départ)
échouait alors à tirer le second des deux ("Duplicate entry ... for key
uq_register_tenant_device"), et ce en boucle à chaque cycle de sync puisque le
watermark avance quand même.

Le fallback de matching (tenant_id, device_id) dans la boucle de pull permet
de fusionner le doublon dans le registre déjà présent localement au lieu de
tenter un INSERT voué à l'échec.
"""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.PosRegister import PosRegister
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


def test_pull_merges_duplicate_device_register_instead_of_failing(db, tenant, monkeypatch):
    device_id = "8acf296f-886f-44b8-a50b-ce9d4c713239"

    # Le cloud renvoie 2 registres distincts pour le MÊME (tenant_id, device_id) —
    # exactement le scénario de production observé (Caisse One / Caisse Two).
    cloud_records = [
        {
            "id": "3bda8232-e02c-4e8a-9626-cfce5d413c3d",
            "tenant_id": tenant.id,
            "warehouse_id": None,
            "name": "Caisse One",
            "device_id": device_id,
            "is_active": True,
            "session_token": None,
            "last_seen": None,
            "is_initial": False,
            "trial_ends_at": None,
            "subscription_started_at": None,
            "subscription_ends_at": None,
            "dedicated_user_id": None,
            "created_at": "2026-07-24T17:18:19",
            "updated_at": "2026-07-24T17:18:19",
        },
        {
            "id": "ac5e542c-2e98-42e1-8bf3-468a4e8d8186",
            "tenant_id": tenant.id,
            "warehouse_id": None,
            "name": "Caisse Two",
            "device_id": device_id,
            "is_active": True,
            "session_token": None,
            "last_seen": None,
            "is_initial": False,
            "trial_ends_at": None,
            "subscription_started_at": None,
            "subscription_ends_at": None,
            "dedicated_user_id": None,
            "created_at": "2026-07-25T09:41:58",
            "updated_at": "2026-07-29T15:35:48",  # plus récent → doit gagner
        },
    ]

    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "pos_register", "model": PosRegister, "direction": "both"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))

    def fake_http_post(url, json, headers, timeout=30):
        assert url.endswith("/api/sync/pull-batch")
        return _FakeResponse({"results": {
            "pos_register": {"records": cloud_records, "has_more": False, "next_since": None},
        }})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)

    result = lss.run_sync(db)

    assert result["ok"] is not False, result
    # Un seul registre local — le doublon a été fusionné, pas dupliqué.
    all_regs = db.query(PosRegister).filter(PosRegister.tenant_id == tenant.id).all()
    assert len(all_regs) == 1
    # Le plus récent (updated_at le plus grand) a gagné sur le nom.
    assert all_regs[0].name == "Caisse Two"
