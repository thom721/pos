"""Suppression d'une caisse (PosRegister) : CashierSession.register_id est une
FK NOT NULL — un hard-delete plantait (IntegrityError → 500 générique) dès
qu'une caisse avait un historique de sessions, malgré un message de
confirmation frontend affirmant à tort que cet historique serait préservé.
Doit maintenant refuser proprement (409) en suggérant la désactivation."""
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import api.models  # noqa: F401
from api.database import Base, get_db
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.models.CashierSession import CashierSession
from api.core.security import create_access_token
from api.core.dt_coerce import now_local
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


@pytest.fixture()
def admin(db, tenant):
    user = User(
        fname="Admin", lname="Test", username="admin_test",
        email="admin_test@t.com", password="x", tenant_id=tenant.id,
        roles=["admin"], permissions=["all"], is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@pytest.fixture()
def admin_headers(admin):
    token = create_access_token({"sub": admin.id, "perm_v": admin.permissions_version or 0})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def warehouse(db, tenant):
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.commit()
    return wh


def test_delete_register_with_session_history_rejected_not_crashed(db, client, tenant, warehouse, admin, admin_headers):
    reg = PosRegister(
        tenant_id=tenant.id, warehouse_id=warehouse.id, name="Caisse avec historique",
        is_active=True, trial_ends_at=now_local() + timedelta(days=30),
    )
    db.add(reg)
    db.flush()
    db.add(CashierSession(
        tenant_id=tenant.id, register_id=reg.id, cashier_id=admin.id,
        opened_at=now_local(), status="closed",
    ))
    db.commit()

    res = client.delete(f"/api/warehouses/{warehouse.id}/registers/{reg.id}", headers=admin_headers)
    assert res.status_code == 409, res.text
    assert "historique" in res.json()["message"].lower()

    # La caisse n'a pas été supprimée.
    remaining = db.query(PosRegister.id).filter_by(id=reg.id).first()
    assert remaining is not None


def test_delete_register_without_history_succeeds(db, client, tenant, warehouse, admin_headers):
    reg = PosRegister(
        tenant_id=tenant.id, warehouse_id=warehouse.id, name="Caisse sans historique",
        is_active=True, trial_ends_at=now_local() + timedelta(days=30),
    )
    db.add(reg)
    db.commit()

    reg_id = reg.id
    res = client.delete(f"/api/warehouses/{warehouse.id}/registers/{reg_id}", headers=admin_headers)
    assert res.status_code == 200, res.text

    remaining = db.query(PosRegister.id).filter_by(id=reg_id).first()
    assert remaining is None
