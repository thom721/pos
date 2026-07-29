"""Bug corrigé : les demandes de paiement soumises depuis une installation
locale/self-hosted (bureau) étaient créées dans la base LOCALE — BillingPayment
n'est jamais synchronisé vers/depuis le cloud (voir SYNC_ENTITIES/_MODEL_MAP),
donc l'admin cloud ne les voyait jamais, et list_payments ne montrait jamais
l'historique réel non plus.

Ces routes suivent maintenant exactement le même principe déjà en place pour
GET /api/billing/license (proxy vers posconnect.ht si BILLING_URL est
configuré, sinon traitement direct — ce serveur EST alors posconnect.ht).
"""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.models.User import User
from api.models.BillingPayment import BillingPayment
import api.routes.billing as billing
from api.routes.billing import SubmitRegisterPaymentRequest


class _FakeResponse:
    def __init__(self, data, status_code=200):
        self._data = data
        self.status_code = status_code

    def json(self):
        return self._data

    def raise_for_status(self):
        pass


class _FakeRequest:
    def __init__(self, headers):
        self.headers = headers


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def tenant_with_register(db):
    tenant = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(tenant)
    db.flush()
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(tenant_id=tenant.id, name="Caisse 1", device_id="dev1", warehouse_id=wh.id)
    db.add(reg)
    user = User(
        tenant_id=tenant.id, fname="A", lname="B", username="ab",
        password="x", roles=["admin"],
    )
    db.add(user)
    db.commit()
    return tenant, wh, reg, user


def test_local_install_proxies_register_payment_submission_to_cloud(db, tenant_with_register, monkeypatch):
    tenant, _wh, reg, user = tenant_with_register
    monkeypatch.setattr(billing.settings, "BILLING_URL", "https://posconnect.ht")
    monkeypatch.setattr(billing.settings, "CLOUD_SYNC_TOKEN", "fake-sync-token")

    calls = {}

    def fake_post(url, json=None, headers=None, timeout=None):
        calls["url"] = url
        calls["json"] = json
        calls["headers"] = headers
        return _FakeResponse({"status": "pending", "payment_count": 1})

    import httpx
    monkeypatch.setattr(httpx, "post", fake_post)

    body = SubmitRegisterPaymentRequest(register_ids=[reg.id], method="cash", months=1, plan_type="monthly")
    result = billing.submit_register_payment(body, db, user)

    assert result == {"status": "pending", "payment_count": 1}
    assert calls["url"] == "https://posconnect.ht/api/billing/submit-register-payment-sync-proxy"
    assert calls["headers"]["Authorization"] == "Bearer fake-sync-token"
    # Aucun BillingPayment ne doit avoir été créé dans la base LOCALE — tout
    # le travail se fait côté cloud via le proxy.
    assert db.query(BillingPayment).count() == 0


def test_direct_mode_creates_payment_locally_when_no_billing_url(db, tenant_with_register, monkeypatch):
    """Quand BILLING_URL n'est pas configuré, ce serveur EST posconnect.ht —
    traitement direct, comme avant."""
    tenant, _wh, reg, user = tenant_with_register
    monkeypatch.setattr(billing.settings, "BILLING_URL", "")
    monkeypatch.setattr(billing.settings, "CLOUD_SYNC_TOKEN", "")

    body = SubmitRegisterPaymentRequest(register_ids=[reg.id], method="cash", months=1, plan_type="monthly")
    result = billing.submit_register_payment(body, db, user)

    assert result["status"] == "pending"
    assert db.query(BillingPayment).filter_by(tenant_id=tenant.id).count() == 1


def test_sync_proxy_endpoint_scopes_to_tenant_from_token(db, tenant_with_register, monkeypatch):
    tenant, _wh, reg, _user = tenant_with_register

    import api.routes.sync as sync_module
    monkeypatch.setattr(sync_module, "_decode_sync_token", lambda token: {"tenant_id": tenant.id})

    body = SubmitRegisterPaymentRequest(register_ids=[reg.id], method="moncash", months=2, plan_type="monthly")
    req = _FakeRequest({"authorization": "Bearer whatever"})
    result = billing.submit_register_payment_sync_proxy(body, req, db)

    assert result["status"] == "pending"
    payment = db.query(BillingPayment).filter_by(tenant_id=tenant.id).first()
    assert payment is not None
    assert payment.method == "moncash"


def test_sync_proxy_rejects_missing_bearer_token(db):
    req = _FakeRequest({})
    body = SubmitRegisterPaymentRequest(register_ids=["x"], method="cash", months=1, plan_type="monthly")
    with pytest.raises(Exception):
        billing.submit_register_payment_sync_proxy(body, req, db)


def test_local_install_proxies_list_payments_to_cloud(db, tenant_with_register, monkeypatch):
    _tenant, _wh, _reg, user = tenant_with_register
    monkeypatch.setattr(billing.settings, "BILLING_URL", "https://posconnect.ht")
    monkeypatch.setattr(billing.settings, "CLOUD_SYNC_TOKEN", "fake-sync-token")

    def fake_get(url, headers=None, timeout=None):
        assert url == "https://posconnect.ht/api/billing/payments-sync-proxy"
        return _FakeResponse([{"id": "cloud-payment-1"}])

    import httpx
    monkeypatch.setattr(httpx, "get", fake_get)

    result = billing.list_payments(db, user)
    assert result == [{"id": "cloud-payment-1"}]
