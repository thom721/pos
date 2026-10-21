"""Bug reel : Role manquait entierement de SYNC_ENTITIES, donc un role
personnalise cree cote cloud admin (ex: "Caissier + Credit") n'atteignait
jamais la base locale. Un caissier qui recevait ce role se voyait refuser
en local une permission (sales.credit) pourtant confirmee accordee cote
cloud via has_permission()/resolve_effective_permissions(). Ces tests
verifient que role est maintenant synchronise, et que le cache en memoire
(TENANT_ROLE_OVERRIDES) est rafraichi sans attendre un redemarrage."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.Role import Role
from api.models.User import User
import api.services.local_sync_service as lss
from api.core.permissions import TENANT_ROLE_OVERRIDES, has_permission, P


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


def test_role_pulled_and_permission_usable_without_restart(db, tenant, monkeypatch):
    TENANT_ROLE_OVERRIDES.pop((tenant.id, "credit_caissier"), None)

    cloud_role = {
        "id": "22222222-2222-2222-2222-222222222222",
        "tenant_id": tenant.id,
        "name": "credit_caissier",
        "label": "Caissier + Credit",
        "color": None,
        "is_builtin": False,
        "permissions": ["sales.credit"],
        "created_at": "2026-10-20T10:00:00",
        "updated_at": "2026-10-20T10:00:00",
    }

    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "role", "model": Role, "direction": "both"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))

    def fake_http_post(url, json, headers, timeout=30):
        if url.endswith("/api/sync/push"):
            return _FakeResponse({"ok": True, "inserted": 0, "updated": 0, "skipped": 0})
        assert url.endswith("/api/sync/pull-batch")
        return _FakeResponse({"results": {
            "role": {"records": [cloud_role], "has_more": False, "next_since": None},
        }})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)

    result = lss.run_sync(db)
    assert result["ok"] is not False, result

    # La ligne existe maintenant en base locale.
    local_role = db.query(Role).filter(
        Role.tenant_id == tenant.id, Role.name == "credit_caissier",
    ).first()
    assert local_role is not None
    assert local_role.permissions == ["sales.credit"]

    # Et la permission est deja utilisable, sans redemarrage du serveur.
    assert has_permission(
        [], ["credit_caissier"], P.SALES_CREDIT, tenant_id=tenant.id,
    ) is True


def test_role_natural_key_fallback_avoids_duplicate_insert_failure(db, tenant, monkeypatch):
    """Un role deja cree en local avant son premier pull (id different de
    celui du cloud) ne doit pas faire echouer l'insert a chaque cycle —
    meme classe de bug que product_price_tier/pos_register."""
    existing = Role(
        tenant_id=tenant.id, name="credit_caissier", label="Caissier + Credit",
        is_builtin=False, permissions=["sales.credit"],
    )
    db.add(existing)
    db.commit()
    local_id = existing.id

    cloud_role = {
        "id": "33333333-3333-3333-3333-333333333333",  # id different
        "tenant_id": tenant.id,
        "name": "credit_caissier",
        "label": "Caissier + Credit (cloud)",
        "color": None,
        "is_builtin": False,
        "permissions": ["sales.credit", "sales.discount"],
        "created_at": now_local().isoformat(),
        "updated_at": (now_local() + timedelta(minutes=5)).isoformat(),
    }

    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "role", "model": Role, "direction": "both"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))

    def fake_http_post(url, json, headers, timeout=30):
        if url.endswith("/api/sync/push"):
            return _FakeResponse({"ok": True, "inserted": 0, "updated": 0, "skipped": 0})
        assert url.endswith("/api/sync/pull-batch")
        return _FakeResponse({"results": {
            "role": {"records": [cloud_role], "has_more": False, "next_since": None},
        }})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)

    result = lss.run_sync(db)
    assert result["ok"] is not False, result

    roles = db.query(Role).filter(
        Role.tenant_id == tenant.id, Role.name == "credit_caissier",
    ).all()
    assert len(roles) == 1, "doublon cree au lieu de mettre a jour la ligne existante"
    assert roles[0].id == local_id
    assert roles[0].permissions == ["sales.credit", "sales.discount"]
