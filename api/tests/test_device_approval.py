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
from api.models.Category import Category
from api.models.Product import Product
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


def _make_user(db, tenant, *, roles, suffix=""):
    tag = f"{'_'.join(roles)}{suffix}"
    user = User(
        fname="U", lname="Test", username=f"user_{tag}",
        email=f"{tag}@t.com", password="x", tenant_id=tenant.id,
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


# ── Régression : rebind hors login ne doit plus déconnecter faussement
#    l'utilisateur courant ("une autre connexion a été ouverte") ────────────

def test_bind_register_device_clears_stale_session_token_on_change():
    """session_token appartient à l'ancien device_id (posé par cloud_login) —
    un rebind vers un device_id différent doit le vider, sinon la prochaine
    requête du véritable utilisateur courant (sid valide mais différent de ce
    token périmé) échoue à tort avec "une autre connexion a été ouverte"."""
    reg = PosRegister(tenant_id="t", name="Caisse", device_id="dev-1",
                       session_token="stale-sid-from-dev-1")
    bind_register_device(reg, "dev-2")
    assert reg.session_token is None


def test_bind_register_device_same_device_keeps_session_token():
    reg = PosRegister(tenant_id="t", name="Caisse", device_id="dev-1",
                       session_token="sid-1")
    bind_register_device(reg, "dev-1")
    assert reg.session_token == "sid-1"


def test_open_session_rebind_does_not_invalidate_current_admin_session(db, client, tenant):
    """Reproduit le bug rapporté en prod : login (register R1 lié à
    device_id="dev-x", session_token="sid-1"), reset_device sur R1, puis
    open_session relie un AUTRE registre au même device_id="dev-x" — avant le
    correctif, ce registre gardait un session_token périmé (None ou une
    autre valeur), et la requête suivante de l'admin (JWT sid="sid-1")
    échouait avec 401 "une autre connexion a été ouverte" alors qu'aucune
    autre connexion n'existait."""
    from api.core.security import create_access_token

    admin = _make_user(db, tenant, roles=["admin"])

    reg1 = db.query(PosRegister).filter_by(tenant_id=tenant.id).first()
    reg1.device_id = "dev-x"
    reg1.session_token = "sid-1"
    db.commit()

    admin_jwt = create_access_token({
        "sub": admin.id, "perm_v": admin.permissions_version or 0,
        "tenant_id": tenant.id, "device_id": "dev-x", "sid": "sid-1",
    })
    headers = {"Authorization": f"Bearer {admin_jwt}"}

    # Toujours valide juste après le "login".
    ok = client.get("/api/warehouses/", headers=headers)
    assert ok.status_code == 200, ok.text

    wh = db.query(Warehouse).filter_by(tenant_id=tenant.id).first()
    reset = client.put(
        f"/api/warehouses/{wh.id}/registers/{reg1.id}",
        json={"reset_device": True},
        headers=headers,
    )
    assert reset.status_code == 200, reset.text

    # Un second registre existant reprend le même device_id (ex: nouvelle
    # ouverture de caisse depuis le même navigateur/appareil).
    reg2 = PosRegister(tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse 2",
                        is_active=True)
    db.add(reg2)
    db.commit()
    from api.services.warehouse_helper import bind_register_device as _bind
    _bind(reg2, "dev-x")
    db.commit()

    # La session admin d'origine (sid="sid-1") doit rester valide — ce n'est
    # PAS une autre connexion, c'est le même utilisateur qui vient d'agir.
    still_ok = client.get("/api/warehouses/", headers=headers)
    assert still_ok.status_code == 200, still_ok.text


def test_session_token_mismatch_still_rejected_when_set(db, client, tenant):
    """Le garde-fou anti-vol de session reste actif : si un registre porte un
    session_token bien défini (posé par un vrai cloud_login) qui ne
    correspond pas au sid du JWT courant, la requête est toujours refusée."""
    from api.core.security import create_access_token

    admin = _make_user(db, tenant, roles=["admin"])
    reg = db.query(PosRegister).filter_by(tenant_id=tenant.id).first()
    reg.device_id = "dev-y"
    reg.session_token = "sid-real-current-login"
    db.commit()

    stale_jwt = create_access_token({
        "sub": admin.id, "perm_v": admin.permissions_version or 0,
        "tenant_id": tenant.id, "device_id": "dev-y", "sid": "sid-OLD-STOLEN",
    })
    headers = {"Authorization": f"Bearer {stale_jwt}"}

    res = client.get("/api/warehouses/", headers=headers)
    assert res.status_code == 401, res.text
    # HTTPException est ré-enveloppée en {"message": ...} par le handler
    # global (api/main.py::http_exception_handler), pas {"detail": ...}.
    assert "autre connexion" in res.json()["message"]


# ── POST /api/sales/ exige une session ouverte (contournement de l'écran) ──

@pytest.fixture()
def product(db, tenant):
    from api.models.StockMovement import StockMovement, StockType

    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    p = Product(name="Produit", category_id=cat.id, sale_price=100,
                purchase_price=50, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    wh = db.query(Warehouse).filter_by(tenant_id=tenant.id).first()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10,
                          tenant_id=tenant.id, warehouse_id=wh.id))
    db.commit()
    return p


def _sale_payload(product):
    return {
        "paid_amount": 100,
        "payment_method": "CASH",
        "items": [{
            "product_id": product.id, "quantity": 1,
            "unit_price": 100, "subtotal": 100,
        }],
    }


def test_create_sale_rejects_direct_api_call_without_open_session(db, client, tenant, product):
    """Un appel API direct (pas via l'écran Caisse, qui exige déjà une
    session) ne doit pas pouvoir créer de vente — sinon l'approbation
    d'appareil serait contournable en sautant simplement open_session."""
    cashier = _make_user(db, tenant, roles=["cashier"])
    headers = {"Authorization": f"Bearer {_token(cashier)}"}

    res = client.post("/api/sales/", json=_sale_payload(product), headers=headers)
    assert res.status_code == 403, res.text
    # HTTPException est ré-enveloppée en {"message": ...} par le handler
    # global (api/main.py::http_exception_handler), pas {"detail": ...}.
    assert "session" in res.json()["message"].lower()


def test_create_sale_succeeds_with_open_session(db, client, tenant, product):
    cashier = _make_user(db, tenant, roles=["cashier"])
    headers = {"Authorization": f"Bearer {_token(cashier)}"}

    # Simule un appareil déjà connu/approuvé (cas normal après la 1ère
    # approbation admin) plutôt que de retester tout le flux d'approbation.
    reg = db.query(PosRegister).filter_by(tenant_id=tenant.id).first()
    reg.device_id = "known-device"
    reg.is_device_approved = True
    db.commit()

    opened = client.post("/api/sessions/open", json={
        "device_id": "known-device", "register_name": "Caisse",
    }, headers=headers)
    assert opened.status_code == 201, opened.text

    res = client.post("/api/sales/", json=_sale_payload(product), headers=headers)
    assert res.status_code == 201, res.text


# ── Même appareil, dépôt différent (bug pré-existant, non lié à cette
#    fonctionnalité, mis au jour en concevant l'approbation) ────────────────

def test_reusing_device_on_different_warehouse_rejected_not_crashed(db, client, tenant):
    """device_id est unique par tenant (uq_register_tenant_device) — avant ce
    correctif, réutiliser un appareil déjà lié à un dépôt sur un AUTRE dépôt
    provoquait une IntegrityError (500) en tentant de réclamer un 2e
    PosRegister avec le même device_id. Doit maintenant échouer proprement
    (409) avec un message clair, sans toucher la base."""
    admin1 = _make_user(db, tenant, roles=["admin"], suffix="1")
    admin2 = _make_user(db, tenant, roles=["admin"], suffix="2")
    headers1 = {"Authorization": f"Bearer {_token(admin1)}"}
    headers2 = {"Authorization": f"Bearer {_token(admin2)}"}

    wh_a = db.query(Warehouse).filter_by(tenant_id=tenant.id).first()
    wh_b = Warehouse(tenant_id=tenant.id, name="Dépôt B", is_active=True)
    db.add(wh_b)
    db.commit()

    # admin1 réclame l'appareil pour le dépôt A et garde sa session ouverte.
    opened = client.post("/api/sessions/open", json={
        "device_id": "shared-tablet", "register_name": "Caisse",
        "warehouse_id": wh_a.id,
    }, headers=headers1)
    assert opened.status_code == 201, opened.text

    # admin2 essaie d'utiliser le MÊME appareil physique pour le dépôt B.
    res = client.post("/api/sessions/open", json={
        "device_id": "shared-tablet", "register_name": "Caisse",
        "warehouse_id": wh_b.id,
    }, headers=headers2)
    assert res.status_code == 409, res.text
    assert res.json()["detail"] == "device_bound_elsewhere"
