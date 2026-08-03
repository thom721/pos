"""require_active_plan (api/core/tenant.py) : une caisse "is_initial" sans
trial_ends_at/subscription_ends_at (jamais réparée) était traitée comme
"en attente de réparation par open_session" et ne bloquait donc JAMAIS les
ventes — y compris quand le trial du TENANT lui-même était déjà expiré, cas
où la réparation ne peut jamais réussir. Une session de caisse ouverte AVANT
l'expiration du plan restait donc utilisable indéfiniment. La vérification
doit maintenant tenter la même réparation puis bloquer si elle échoue."""
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
from api.models.Category import Category
from api.models.Product import Product
from api.models.StockMovement import StockMovement, StockType
from api.models.CashierSession import CashierSession
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


def _setup(db, *, tenant_trial_delta):
    tenant = Tenant(
        business_name="T", owner_email="t@t.com", slug="t",
        trial_ends_at=now_local() + tenant_trial_delta if tenant_trial_delta else None,
    )
    db.add(tenant)
    db.flush()
    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    product = Product(name="Prod", category_id=cat.id, sale_price=100,
                       purchase_price=50, tenant_id=tenant.id)
    db.add(product)
    db.flush()
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10,
                          tenant_id=tenant.id, warehouse_id=wh.id))

    user = User(fname="U", lname="T", username="cashier1", email="c1@t.com",
                password="x", tenant_id=tenant.id, roles=["cashier"],
                permissions=[], is_active=True)
    db.add(user)
    db.commit()
    db.refresh(user)

    # Caisse initiale, JAMAIS réparée (trial_ends_at/subscription_ends_at
    # tous les deux NULL) — le scénario que le garde-fou d'origine laissait
    # passer indéfiniment.
    reg = PosRegister(tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse principale",
                       is_active=True, device_id="dev1", is_device_approved=True,
                       is_initial=True)
    db.add(reg)
    db.flush()
    db.add(CashierSession(tenant_id=tenant.id, register_id=reg.id, cashier_id=user.id,
                           warehouse_id=wh.id, opened_at=now_local(), status="open",
                           opening_balance=0))
    db.commit()

    token = create_access_token({
        "sub": user.id, "tenant_id": tenant.id, "device_id": "dev1",
        "sid": None, "perm_v": 0,
    })
    return product, token, reg


def _sell(client, product, token):
    return client.post("/api/sales/", json={
        "paid_amount": 100, "payment_method": "CASH",
        "items": [{"product_id": product.id, "quantity": 1, "unit_price": 100, "subtotal": 100}],
    }, headers={"Authorization": f"Bearer {token}"})


def test_unrepaired_initial_register_blocked_when_tenant_trial_also_expired(db, client):
    product, token, _ = _setup(db, tenant_trial_delta=timedelta(days=-5))
    res = _sell(client, product, token)
    assert res.status_code == 402, res.text
    assert "abonnement" in res.json()["message"].lower()


def test_unrepaired_initial_register_repaired_and_allowed_when_tenant_trial_still_valid(db, client):
    product, token, reg = _setup(db, tenant_trial_delta=timedelta(days=10))
    res = _sell(client, product, token)
    assert res.status_code == 201, res.text
    db.refresh(reg)
    assert reg.trial_ends_at is not None


def test_unrepaired_initial_register_blocked_when_tenant_has_no_trial_at_all(db, client):
    product, token, _ = _setup(db, tenant_trial_delta=None)
    res = _sell(client, product, token)
    assert res.status_code == 402, res.text
