"""Bug corrigé : installation via CODE (sync_token_prefetched) laisse
data.password vide côté installeur — le mot de passe local ne peut alors pas
être dérivé du vrai mot de passe cloud du tenant. _pull_admin_password_from_cloud
va chercher immédiatement le vrai hash sur le cloud (au lieu d'attendre le
premier cycle de sync), pour que le tenant puisse se connecter en local avec
les mêmes identifiants que sur le web, sans étape supplémentaire."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.User import User
from api.routes.setup import _pull_admin_password_from_cloud


class _FakeResponse:
    def __init__(self, status_code, data):
        self.status_code = status_code
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
def local_admin(db):
    tenant = Tenant(business_name="T", owner_email="owner@t.com", slug="t")
    db.add(tenant)
    db.flush()
    user = User(
        tenant_id=tenant.id, fname="Owner", lname="", username="owner",
        email="owner@t.com", password="placeholder-hash-not-real",
        offline_hash=None, roles=["admin"], permissions=["all"],
    )
    db.add(user)
    db.commit()
    return user


def test_recovers_real_password_hash_from_cloud(db, local_admin, monkeypatch):
    real_hash = "$argon2id$real-cloud-hash"
    real_offline_hash = "abc123offlinehash"

    def fake_get(url, params=None, headers=None, timeout=None):
        assert params["entity_type"] == "user"
        return _FakeResponse(200, {"records": [
            {"id": local_admin.id, "email": "owner@t.com",
             "password": real_hash, "offline_hash": real_offline_hash},
        ]})

    monkeypatch.setattr("httpx.get", fake_get)

    _pull_admin_password_from_cloud(
        "https://cloud.example", "fake-token", local_admin.id, "owner@t.com", db
    )

    db.refresh(local_admin)
    assert local_admin.password == real_hash
    assert local_admin.offline_hash == real_offline_hash


def test_matches_by_email_when_id_unknown(db, local_admin, monkeypatch):
    """Le user_id prefetched peut être vide (redeem-code path) — le matching
    par email doit suffire."""
    real_hash = "$argon2id$other-hash"

    def fake_get(url, params=None, headers=None, timeout=None):
        return _FakeResponse(200, {"records": [
            {"id": "some-other-uuid-not-matching", "email": "owner@t.com",
             "password": real_hash, "offline_hash": None},
        ]})

    monkeypatch.setattr("httpx.get", fake_get)

    _pull_admin_password_from_cloud(
        "https://cloud.example", "fake-token", "", "owner@t.com", db
    )

    db.refresh(local_admin)
    assert local_admin.password == real_hash


def test_no_matching_record_leaves_password_untouched(db, local_admin, monkeypatch):
    def fake_get(url, params=None, headers=None, timeout=None):
        return _FakeResponse(200, {"records": [
            {"id": "unrelated", "email": "someone-else@t.com", "password": "x"},
        ]})

    monkeypatch.setattr("httpx.get", fake_get)

    _pull_admin_password_from_cloud(
        "https://cloud.example", "fake-token", "unknown-id", "owner@t.com", db
    )

    db.refresh(local_admin)
    assert local_admin.password == "placeholder-hash-not-real"


def test_cloud_unreachable_does_not_raise(db, local_admin, monkeypatch):
    def fake_get(*a, **kw):
        raise ConnectionError("network down")

    monkeypatch.setattr("httpx.get", fake_get)

    # Ne doit jamais lever — non-bloquant, la sync corrigera plus tard.
    _pull_admin_password_from_cloud(
        "https://cloud.example", "fake-token", local_admin.id, "owner@t.com", db
    )
    db.refresh(local_admin)
    assert local_admin.password == "placeholder-hash-not-real"
