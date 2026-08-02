"""Approbation d'appareil pour ouvrir une caisse (voir plan
synchronous-percolating-sparrow.md) : un identifiant/mot de passe valide ne
suffit plus à transiger depuis n'importe quel appareil — seul le login reste
toujours possible ; ouvrir une session de caisse exige que l'appareil soit
déjà connu (PosRegister.device_id inchangé) ou explicitement approuvé par un
admin/manager du tenant. Les rôles admin/manager restent exemptés."""
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
from api.models.PosRegister import PosRegister
from api.models.Warehouse import Warehouse
from api.core.security import create_access_token
from api.core.dt_coerce import now_local
from api.services.warehouse_helper import bind_register_device
import api.main as main_module


# ── bind_register_device (unitaire, sans HTTP) ──────────────────────────────

def test_bind_register_device_same_device_keeps_approval():
    reg = PosRegister(tenant_id="t", name="Caisse", device_id="dev-1", is_device_approved=True)
    bind_register_device(reg, "dev-1")
    assert reg.is_device_approved is True
    assert reg.device_id == "dev-1"


def test_bind_register_device_new_device_revokes_approval():
    reg = PosRegister(tenant_id="t", name="Caisse", device_id="dev-1", is_device_approved=True)
    bind_register_device(reg, "dev-2")
    assert reg.is_device_approved is False
    assert reg.device_id == "dev-2"


def test_bind_register_device_first_claim_from_none_revokes_approval():
    reg = PosRegister(tenant_id="t", name="Caisse", device_id=None, is_device_approved=True)
    bind_register_device(reg, "dev-1")
    assert reg.is_device_approved is False
    assert reg.device_id == "dev-1"


# ── HTTP : open_session refuse/accepte selon approbation + rôle ─────────────

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
    # Une caisse libre non réclamée — comme celle créée automatiquement pour
    # tout tenant réel (register_tenant) ; sans elle, open_session renvoie
    # "no_registers" avant même d'atteindre la vérification d'approbation.
    wh = Warehouse(tenant_id=t.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    db.add(PosRegister(
        tenant_id=t.id, warehouse_id=wh.id, name="Caisse principale",
        is_active=True, is_initial=True,
        trial_ends_at=now_local() + timedelta(days=30),
    ))
    db.commit()
    return t


def _make_user(db, tenant, *, roles):
    user = User(
        fname="U", lname="Test", username=f"user_{'_'.join(roles)}",
        email=f"{'_'.join(roles)}@t.com", password="x", tenant_id=tenant.id,
        roles=roles, permissions=[], is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _token(user) -> str:
    return create_access_token({"sub": user.id, "perm_v": user.permissions_version or 0})


def test_open_session_rejects_unapproved_device_for_cashier(db, client, tenant):
    cashier = _make_user(db, tenant, roles=["cashier"])
    headers = {"Authorization": f"Bearer {_token(cashier)}"}

    res = client.post("/api/sessions/open", json={
        "device_id": "brand-new-device",
        "register_name": "Caisse",
    }, headers=headers)

    # Une caisse est créée/réclamée par _get_or_create_register (device_id
    # jamais vu → is_device_approved=False) puis open_session la refuse.
    assert res.status_code == 403, res.text
    assert res.json()["detail"] == "device_pending_approval"


def test_open_session_allows_manager_on_unapproved_device(db, client, tenant):
    manager = _make_user(db, tenant, roles=["manager"])
    headers = {"Authorization": f"Bearer {_token(manager)}"}

    res = client.post("/api/sessions/open", json={
        "device_id": "brand-new-device-2",
        "register_name": "Caisse",
    }, headers=headers)

    assert res.status_code == 201, res.text


def test_admin_approval_unblocks_session_open(db, client, tenant):
    cashier = _make_user(db, tenant, roles=["cashier"])
    admin = _make_user(db, tenant, roles=["admin"])

    cashier_headers = {"Authorization": f"Bearer {_token(cashier)}"}
    admin_headers = {"Authorization": f"Bearer {_token(admin)}"}

    denied = client.post("/api/sessions/open", json={
        "device_id": "device-pending",
        "register_name": "Caisse",
    }, headers=cashier_headers)
    assert denied.status_code == 403

    reg = db.query(PosRegister).filter_by(tenant_id=tenant.id, device_id="device-pending").first()
    assert reg is not None
    assert reg.is_device_approved is False

    wh_res = client.get(f"/api/warehouses/", headers=admin_headers)
    assert wh_res.status_code == 200, wh_res.text
    warehouse_id = reg.warehouse_id or (wh_res.json()[0]["id"] if wh_res.json() else None)
    assert warehouse_id, "attendu un dépôt par défaut créé automatiquement pour le tenant"

    approve = client.put(
        f"/api/warehouses/{warehouse_id}/registers/{reg.id}",
        json={"is_device_approved": True},
        headers=admin_headers,
    )
    assert approve.status_code == 200, approve.text
    assert approve.json()["is_device_approved"] is True

    allowed = client.post("/api/sessions/open", json={
        "device_id": "device-pending",
        "register_name": "Caisse",
    }, headers=cashier_headers)
    assert allowed.status_code == 201, allowed.text


def test_reset_device_clears_and_revokes_approval(db, client, tenant):
    admin = _make_user(db, tenant, roles=["admin"])
    admin_headers = {"Authorization": f"Bearer {_token(admin)}"}

    opened = client.post("/api/sessions/open", json={
        "device_id": "old-phone",
        "register_name": "Caisse",
    }, headers=admin_headers)
    assert opened.status_code == 201, opened.text
    reg = db.query(PosRegister).filter_by(tenant_id=tenant.id, device_id="old-phone").first()
    assert reg is not None
    warehouse_id = reg.warehouse_id

    reset = client.put(
        f"/api/warehouses/{warehouse_id}/registers/{reg.id}",
        json={"reset_device": True},
        headers=admin_headers,
    )
    assert reset.status_code == 200, reset.text
    db.refresh(reg)
    assert reg.device_id is None
    assert reg.is_device_approved is False


def test_create_register_grants_no_trial_period(db, client, tenant):
    """Seule la toute première caisse d'un dépôt (is_initial=True) a droit à
    une période d'essai — une caisse ajoutée ensuite via 'Ajouter une caisse'
    doit être payée immédiatement, sans essai gratuit."""
    admin = _make_user(db, tenant, roles=["admin"])
    headers = {"Authorization": f"Bearer {_token(admin)}"}

    wh = db.query(Warehouse).filter_by(tenant_id=tenant.id).first()
    res = client.post(
        f"/api/warehouses/{wh.id}/registers",
        json={"name": "Caisse 2", "force": True},
        headers=headers,
    )
    assert res.status_code == 201, res.text

    reg = db.query(PosRegister).filter_by(tenant_id=tenant.id, name="Caisse 2").first()
    assert reg is not None
    assert reg.is_initial is False
    assert reg.trial_ends_at is None
    assert reg.subscription_ends_at is None


def test_preexisting_register_unaffected_by_migration_default(db):
    """Simule une caisse déjà en usage avant ce correctif (is_device_approved
    par défaut True côté colonne) — bind_register_device ne la révoque QUE si
    le device_id change réellement, donc aucune régression pour l'existant."""
    reg = PosRegister(tenant_id="t", name="Caisse", device_id="already-known", is_device_approved=True)
    # Le même appareil se reconnecte (comportement normal, aucun changement).
    bind_register_device(reg, "already-known")
    assert reg.is_device_approved is True
