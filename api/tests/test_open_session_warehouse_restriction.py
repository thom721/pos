"""Un cashier restreint à un sous-ensemble de dépôts (User.warehouse_id non
vide) ne doit jamais pouvoir ouvrir une session de caisse sur un dépôt hors
de cette liste — même faille que celle fermée dans sale_service.create_sale,
jamais reproduite dans open_session/_get_or_create_register (cashier_sessions.py).

Scénario constaté : un appareil déjà lié (device_id) à la caisse d'un AUTRE
dépôt était réutilisé tel quel dès que le client n'envoyait aucun
warehouse_id explicite dans la requête d'ouverture, sans aucune vérification
de la liste de dépôts autorisés de l'utilisateur connecté."""
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
from api.core.dt_coerce import now_local
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


def _token(user, tenant, device_id):
    return create_access_token({
        "sub": user.id, "tenant_id": tenant.id, "device_id": device_id,
        "sid": None, "perm_v": 0,
    })


def _setup(db):
    tenant = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(tenant)
    db.flush()

    depot_a = Warehouse(tenant_id=tenant.id, name="NES", is_active=True, is_default=True)
    depot_b = Warehouse(tenant_id=tenant.id, name="PROMESSE DE DIEU", is_active=True, is_default=False)
    db.add_all([depot_a, depot_b])
    db.flush()

    # Caisse deja en service sur le depot A, liee a un appareil, pas dediee.
    reg_a = PosRegister(
        tenant_id=tenant.id, warehouse_id=depot_a.id, name="Caisse A",
        is_active=True, device_id="dev-shared", is_device_approved=True,
        trial_ends_at=now_local() + timedelta(days=30),
    )
    # Caisse du depot B, appareil deja approuve (cas normal d'un cashier qui
    # a deja utilise cet appareil avant) — device_id=None testerait plutot le
    # flux d'approbation d'un nouvel appareil, hors sujet ici.
    reg_b = PosRegister(
        tenant_id=tenant.id, warehouse_id=depot_b.id, name="Caisse B",
        is_active=True, device_id="dev-new", is_device_approved=True,
        trial_ends_at=now_local() + timedelta(days=30),
    )
    db.add_all([reg_a, reg_b])
    db.flush()

    cashier = User(
        fname="Rous", lname="", username="rous", email="rous@t.com", password="x",
        tenant_id=tenant.id, roles=["cashier"], permissions=["cashier"],
        is_active=True, warehouse_id=[depot_b.id],
    )
    admin = User(
        fname="Admin", lname="", username="admin", email="admin@t.com", password="x",
        tenant_id=tenant.id, roles=["admin"], permissions=["all"],
        is_active=True, warehouse_id=[],
    )
    db.add_all([cashier, admin])
    db.commit()
    db.refresh(cashier)
    db.refresh(admin)
    return tenant, depot_a, depot_b, reg_a, reg_b, cashier, admin


def test_restricted_cashier_blocked_from_other_depot_shared_device(db, client):
    tenant, depot_a, depot_b, reg_a, reg_b, cashier, admin = _setup(db)
    token = _token(cashier, tenant, "dev-shared")

    res = client.post("/api/sessions/open", json={
        "device_id": "dev-shared", "register_name": "Caisse A",
    }, headers={"Authorization": f"Bearer {token}"})

    assert res.status_code == 403, res.text
    assert res.json()["detail"] == "register_warehouse_forbidden"


def test_restricted_cashier_can_open_her_own_depot(db, client):
    tenant, depot_a, depot_b, reg_a, reg_b, cashier, admin = _setup(db)
    token = _token(cashier, tenant, "dev-new")

    res = client.post("/api/sessions/open", json={
        "device_id": "dev-new", "register_name": "Caisse B",
        "warehouse_id": depot_b.id,
    }, headers={"Authorization": f"Bearer {token}"})

    assert res.status_code == 201, res.text


def test_unrestricted_admin_can_still_use_shared_device(db, client):
    tenant, depot_a, depot_b, reg_a, reg_b, cashier, admin = _setup(db)
    token = _token(admin, tenant, "dev-shared")

    res = client.post("/api/sessions/open", json={
        "device_id": "dev-shared", "register_name": "Caisse A",
    }, headers={"Authorization": f"Bearer {token}"})

    assert res.status_code == 201, res.text
