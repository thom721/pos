"""GET /api/sessions/current ne doit jamais renvoyer la session ouverte d'un
AUTRE caissier sur la même caisse — même après déconnexion/reconnexion."""
from types import SimpleNamespace

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
from api.database import Base
from api.models.CashierSession import CashierSession
from api.models.PosRegister import PosRegister
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.routes.cashier_sessions import get_current_session


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


def _user(stub_id, tenant_id):
    return SimpleNamespace(id=stub_id, tenant_id=tenant_id, roles=["cashier"])


def test_other_cashiers_open_session_is_not_returned(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(tenant_id=t.id, warehouse_id=wh.id, name="Caisse 1",
                      device_id="dev-1", is_active=True, is_device_approved=True)
    db.add(reg)
    db.flush()
    cashier_a = User(tenant_id=t.id, fname="A", lname="A", username="cashier_a",
                      email="a@t.com", password="x", roles=["cashier"])
    cashier_b = User(tenant_id=t.id, fname="B", lname="B", username="cashier_b",
                      email="b@t.com", password="x", roles=["cashier"])
    db.add_all([cashier_a, cashier_b])
    db.flush()
    db.add(CashierSession(tenant_id=t.id, register_id=reg.id, cashier_id=cashier_a.id,
                          warehouse_id=wh.id, opened_at=now_local(), status="open"))
    db.commit()

    res = get_current_session(device_id="dev-1", warehouse_id=None, db=db,
                              current_user=_user(cashier_b.id, t.id))
    assert res["session"] is None, "la session d'un autre caissier ne doit pas fuiter"


def test_own_open_session_is_returned(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(tenant_id=t.id, warehouse_id=wh.id, name="Caisse 1",
                      device_id="dev-1", is_active=True, is_device_approved=True)
    db.add(reg)
    db.flush()
    cashier_a = User(tenant_id=t.id, fname="A", lname="A", username="cashier_a",
                      email="a@t.com", password="x", roles=["cashier"])
    db.add(cashier_a)
    db.flush()
    sess = CashierSession(tenant_id=t.id, register_id=reg.id, cashier_id=cashier_a.id,
                          warehouse_id=wh.id, opened_at=now_local(), status="open")
    db.add(sess)
    db.commit()

    res = get_current_session(device_id="dev-1", warehouse_id=None, db=db,
                              current_user=_user(cashier_a.id, t.id))
    assert res["session"] is not None
    assert res["session"]["id"] == sess.id
