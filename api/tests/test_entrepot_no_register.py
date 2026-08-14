"""Un entrepôt (Warehouse.is_entrepot=True) ne peut jamais avoir de caisse —
ni via création manuelle (POST /api/warehouses/{id}/registers), ni via le
chemin de création automatique à l'ouverture de session
(_get_or_create_register). Auparavant, aucun des deux ne vérifiait
is_entrepot — seul le bouton "Ajouter une caisse" était masqué côté UI, ce
qui restait contournable par un appel API direct."""
from datetime import timedelta

import pytest
from fastapi import HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import api.models  # noqa: F401
from api.database import Base, get_db
from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.routes.warehouse import create_register, RegisterCreate
from api.routes.cashier_sessions import _get_or_create_register


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
def tenant(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    return t


@pytest.fixture()
def entrepot(db, tenant):
    e = Warehouse(tenant_id=tenant.id, name="Entrepôt", is_entrepot=True, is_claimed=True)
    db.add(e)
    db.commit()
    return e


@pytest.fixture()
def admin_user(db, tenant):
    u = User(
        tenant_id=tenant.id, fname="A", lname="B", username="admin",
        email="admin@t.com", password="x", roles=["admin"], is_active=True,
    )
    db.add(u)
    db.commit()
    return u


def test_create_register_rejected_for_entrepot(db, tenant, entrepot, admin_user):
    with pytest.raises(HTTPException) as exc:
        create_register(
            entrepot.id, RegisterCreate(name="Caisse", force=True),
            db=db, current_user=admin_user,
        )
    assert exc.value.status_code == 400
    assert "entrepôt" in exc.value.detail.lower()
    assert db.query(PosRegister).filter_by(warehouse_id=entrepot.id).count() == 0


def test_create_register_allowed_for_regular_warehouse(db, tenant, admin_user):
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.commit()

    reg = create_register(
        wh.id, RegisterCreate(name="Caisse", force=True),
        db=db, current_user=admin_user,
    )
    assert reg.warehouse_id == wh.id


def test_get_or_create_register_rejects_entrepot_warehouse_id(db, tenant, entrepot):
    result = _get_or_create_register(
        db, tenant.id, device_id="dev-1", name="Caisse",
        force=True, warehouse_id=entrepot.id, is_admin=True,
    )
    assert isinstance(result, JSONResponse)
    assert result.status_code == 400
    assert db.query(PosRegister).filter_by(warehouse_id=entrepot.id).count() == 0
