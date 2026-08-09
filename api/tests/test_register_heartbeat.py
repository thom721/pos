"""Le heartbeat périodique (app.dart::_sendHeartbeat) est la seule source
permettant à l'admin de savoir quelle version de l'app tourne sur chaque
caisse — avant ce correctif, le client ne remontait jamais sa version."""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import api.models  # noqa: F401
from api.database import Base, get_db
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.PosRegister import PosRegister
from api.core.security import create_access_token
import api.main as main_module


@pytest.fixture()
def engine():
    return create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )


@pytest.fixture()
def db(engine):
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def client(engine):
    TestSession = sessionmaker(bind=engine)

    def _override_get_db():
        db = TestSession()
        try:
            yield db
        finally:
            db.close()

    main_module.app.dependency_overrides[get_db] = _override_get_db
    with TestClient(main_module.app, raise_server_exceptions=True) as c:
        yield c
    main_module.app.dependency_overrides.clear()


@pytest.fixture()
def tenant(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    return t


def _make_user(db, tenant):
    user = User(
        fname="U", lname="Test", username="user1", email="u1@t.com",
        password="x", tenant_id=tenant.id, roles=["cashier"],
        permissions=[], is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _token(user) -> str:
    return create_access_token({"sub": user.id, "perm_v": user.permissions_version or 0})


def test_heartbeat_records_app_version_and_build(db, client, tenant):
    user = _make_user(db, tenant)
    reg = PosRegister(
        tenant_id=tenant.id, name="Caisse", device_id="dev-1", is_active=True,
    )
    db.add(reg)
    db.commit()

    res = client.post("/api/warehouses/registers/heartbeat", json={
        "device_id": "dev-1", "app_version": "2.0.0", "app_build": 9,
    }, headers={"Authorization": f"Bearer {_token(user)}"})

    assert res.status_code == 200, res.text
    db.refresh(reg)
    assert reg.app_version == "2.0.0"
    assert reg.app_build == 9
    assert reg.last_seen is not None


def test_heartbeat_without_version_leaves_it_unset(db, client, tenant):
    """Compat avec un client plus ancien qui n'envoie pas encore ces champs."""
    user = _make_user(db, tenant)
    reg = PosRegister(
        tenant_id=tenant.id, name="Caisse", device_id="dev-2", is_active=True,
    )
    db.add(reg)
    db.commit()

    res = client.post("/api/warehouses/registers/heartbeat", json={
        "device_id": "dev-2",
    }, headers={"Authorization": f"Bearer {_token(user)}"})

    assert res.status_code == 200, res.text
    db.refresh(reg)
    assert reg.app_version is None
    assert reg.app_build is None
