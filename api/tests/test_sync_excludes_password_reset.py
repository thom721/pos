"""password_reset_code/password_reset_expires_at ne doivent jamais traverser
la synchro — un code de réinitialisation actif (15 min) répliqué entre local
et cloud exposerait inutilement un identifiant de contournement
d'authentification sur un système qui ne l'a pas généré et ne le validera
jamais (reset-password valide toujours contre le backend qui a reçu la
requête, jamais par proxy)."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.User import User
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


def test_password_reset_fields_excluded_from_push_payload(db, tenant):
    user = User(
        tenant_id=tenant.id, fname="A", lname="B", username="ab",
        email="ab@t.com", password="hashed", roles=["cashier"], is_active=True,
        password_reset_code="123456",
        password_reset_expires_at=now_local() + timedelta(minutes=15),
    )
    db.add(user)
    db.commit()

    payload = lss._serialize([user], lss._EXCLUDE_PUSH)[0]
    assert "password_reset_code" not in payload
    assert "password_reset_expires_at" not in payload
    assert "password" not in payload  # déjà exclu — sanity check du fixture


def test_password_reset_fields_never_applied_from_pull(db, tenant, monkeypatch):
    user = User(
        tenant_id=tenant.id, fname="A", lname="B", username="ab",
        email="ab@t.com", password="hashed", roles=["cashier"], is_active=True,
    )
    db.add(user)
    db.commit()

    cloud_record = {
        "id": user.id,
        "tenant_id": tenant.id,
        "fname": "A", "lname": "B", "username": "ab", "email": "ab@t.com",
        "password": "hashed", "roles": ["cashier"], "is_active": True,
        "permissions": [], "permissions_version": 0,
        "must_change_password": False, "warehouse_id": None,
        "phone": None, "address": None, "offline_hash": None,
        # Le cloud pourrait renvoyer ces champs (aucune exclusion cote
        # serveur, voir api/routes/sync.py::_row_to_dict) — le poste local
        # doit les ignorer a la reception malgre tout.
        "password_reset_code": "999999",
        "password_reset_expires_at": (now_local() + timedelta(minutes=15)).isoformat(),
        "created_at": now_local().isoformat(),
        "updated_at": (now_local() + timedelta(seconds=1)).isoformat(),
    }

    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "user", "model": User, "direction": "both"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))

    def fake_http_post(url, json, headers, timeout=30):
        if url.endswith("/api/sync/push"):
            return _FakeResponse({"ok": True, "inserted": 0, "updated": 0, "skipped": 0})
        assert url.endswith("/api/sync/pull-batch")
        return _FakeResponse({"results": {
            "user": {"records": [cloud_record], "has_more": False, "next_since": None},
        }})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)

    result = lss.run_sync(db)
    assert result["ok"] is not False, result

    db.refresh(user)
    assert user.password_reset_code is None
    assert user.password_reset_expires_at is None
