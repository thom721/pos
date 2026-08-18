"""Prix de renouvellement (PlatformConfig.renewal_price_per_caisse_*/_depot_*) :
après la première année d'abonnement (365 jours), chaque caisse ou entrepôt
(initial ou supplémentaire, sans distinction) bascule du prix normal
(price_per_extra_caisse_*/price_per_extra_depot_*) vers le prix de
renouvellement — voir billing._renewal_pricing / _compute_plan_usage /
_submit_register_payment_for_tenant / _submit_entrepot_payment_for_tenant.
L'ancre est PosRegister.subscription_started_at pour une caisse,
Warehouse.created_at pour un entrepôt (pas de subscription_started_at sur ce
modèle — voir clarification utilisateur)."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
from api.database import Base
from api.models.PlatformConfig import PlatformConfig
from api.models.PosRegister import PosRegister
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
import api.routes.billing as billing
from api.routes.billing import (
    SubmitEntrepotPaymentRequest,
    SubmitRegisterPaymentRequest,
    _compute_plan_usage,
    _renewal_pricing,
)


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def cfg(db):
    c = PlatformConfig(
        price_per_extra_caisse_htg=500, price_per_extra_caisse_usd=4,
        renewal_price_per_caisse_htg=800, renewal_price_per_caisse_usd=6,
        price_per_extra_depot_htg=500, price_per_extra_depot_usd=4,
        renewal_price_per_depot_htg=900, renewal_price_per_depot_usd=7,
        annual_discount_pct=0,
    )
    db.add(c)
    db.flush()
    return c


@pytest.fixture()
def tenant(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    return t


def test_renewal_pricing_helper_switches_after_365_days():
    now = now_local()
    price, effective_at = _renewal_pricing(now - timedelta(days=400), now, 500, 800)
    assert price == 800
    assert effective_at == now - timedelta(days=400) + timedelta(days=365)


def test_renewal_pricing_helper_before_365_days():
    now = now_local()
    price, _ = _renewal_pricing(now - timedelta(days=100), now, 500, 800)
    assert price == 500


def test_renewal_pricing_helper_no_started_at():
    now = now_local()
    price, effective_at = _renewal_pricing(None, now, 500, 800)
    assert price == 500
    assert effective_at is None


def test_plan_usage_switches_register_price_after_first_year(db, tenant, cfg):
    now = now_local()
    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_default=True)
    db.add(wh)
    db.flush()

    old_reg = PosRegister(
        tenant_id=tenant.id, name="Vieille caisse", device_id="dev-old",
        warehouse_id=wh.id, is_initial=True,
        subscription_started_at=now - timedelta(days=400),
    )
    new_reg = PosRegister(
        tenant_id=tenant.id, name="Nouvelle caisse", device_id="dev-new",
        warehouse_id=wh.id, is_initial=False,
        subscription_started_at=now - timedelta(days=10),
    )
    db.add_all([old_reg, new_reg])
    db.commit()

    usage = _compute_plan_usage(tenant, db, cfg)
    by_name = {r["name"]: r for r in usage["registers"]}
    assert by_name["Vieille caisse"]["monthly_htg"] == 800  # renouvellement
    assert by_name["Nouvelle caisse"]["monthly_htg"] == 500  # prix normal
    assert usage["total_monthly_htg"] == 1300
    assert usage["renewal_price_per_caisse_htg"] == 800


def test_plan_usage_switches_entrepot_price_using_created_at(db, tenant, cfg):
    now = now_local()
    old_ent = Warehouse(tenant_id=tenant.id, name="Vieil entrepot", is_entrepot=True)
    db.add(old_ent)
    db.flush()
    old_ent.created_at = now - timedelta(days=400)

    new_ent = Warehouse(tenant_id=tenant.id, name="Nouvel entrepot", is_entrepot=True)
    db.add(new_ent)
    db.flush()
    new_ent.created_at = now - timedelta(days=10)
    db.commit()

    usage = _compute_plan_usage(tenant, db, cfg)
    by_name = {e["name"]: e for e in usage["entrepots"]}
    assert by_name["Vieil entrepot"]["monthly_htg"] == 900  # renouvellement
    assert by_name["Nouvel entrepot"]["monthly_htg"] == 500  # prix normal


def test_submit_register_payment_charges_renewal_price_for_old_register(db, tenant, cfg, monkeypatch):
    monkeypatch.setattr(billing.settings, "BILLING_URL", "")
    monkeypatch.setattr(billing.settings, "CLOUD_SYNC_TOKEN", "")
    now = now_local()

    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(
        tenant_id=tenant.id, name="Caisse", device_id="dev1", warehouse_id=wh.id,
        subscription_started_at=now - timedelta(days=400),
    )
    db.add(reg)
    user = User(tenant_id=tenant.id, fname="A", lname="B", username="ab",
                password="x", roles=["admin"])
    db.add(user)
    db.commit()

    body = SubmitRegisterPaymentRequest(register_ids=[reg.id], method="cash", months=1, plan_type="monthly")
    result = billing.submit_register_payment(body, db, user)
    assert result["amount_htg"] == 800  # renewal_price_per_caisse_htg, pas 500


def test_submit_entrepot_payment_charges_renewal_price_for_old_entrepot(db, tenant, cfg, monkeypatch):
    monkeypatch.setattr(billing.settings, "BILLING_URL", "")
    monkeypatch.setattr(billing.settings, "CLOUD_SYNC_TOKEN", "")
    now = now_local()

    ent = Warehouse(tenant_id=tenant.id, name="Entrepot", is_entrepot=True)
    db.add(ent)
    db.flush()
    ent.created_at = now - timedelta(days=400)
    user = User(tenant_id=tenant.id, fname="A", lname="B", username="ab",
                password="x", roles=["admin"])
    db.add(user)
    db.commit()

    body = SubmitEntrepotPaymentRequest(entrepot_ids=[ent.id], method="cash", months=1, plan_type="monthly")
    result = billing.submit_entrepot_payment(body, db, user)
    assert result["amount_htg"] == 900  # renewal_price_per_depot_htg, pas 500
