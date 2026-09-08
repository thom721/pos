"""Confirmation de paiement caisse (api/routes/admin.py confirm_payment) —
la date de départ du nouveau cycle dépend du statut de la caisse :
- encore active (renouvellement en cours de cycle) → prolonge depuis
  l'ancienne date de fin, aucun jour perdu.
- déjà expirée, sans trial_included_in_billing → repart d'aujourd'hui.
- premier paiement (jamais eu d'abonnement payé) ET
  PlatformConfig.trial_included_in_billing=True → repart de la date de
  création de la caisse (les jours d'essai consommés sont déduits), sauf
  si la caisse a plus de `days` jours (repli sur aujourd'hui pour ne pas
  générer une date déjà expirée) — même règle que _activate_tenant pour le
  plan principal du tenant."""
import json
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
from api.database import Base
from api.models.BillingPayment import BillingPayment
from api.models.PlatformConfig import PlatformConfig
from api.models.PosRegister import PosRegister
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.routes.admin import ConfirmPaymentPayload, confirm_payment


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
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


def _cfg(db, trial_included: bool):
    c = PlatformConfig(trial_included_in_billing=trial_included)
    db.add(c)
    db.flush()
    return c


def _payment_for(db, tenant, reg):
    p = BillingPayment(
        tenant_id=tenant.id, invoice_number=f"REG-TEST-{reg.id[:8]}",
        method="cash", amount=500, currency="HTG", months=1,
        status="pending", plan_type="monthly",
        register_ids_json=json.dumps([reg.id]),
    )
    db.add(p)
    db.commit()
    return p


def test_renewal_while_still_active_extends_from_old_end_date(db, tenant):
    _cfg(db, trial_included=False)
    now = now_local()
    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(
        tenant_id=tenant.id, name="Caisse", device_id="dev1", warehouse_id=wh.id,
        subscription_started_at=now - timedelta(days=100),
        subscription_ends_at=now + timedelta(days=10),
    )
    db.add(reg)
    payment = _payment_for(db, tenant, reg)

    confirm_payment(payment.id, ConfirmPaymentPayload(), db=db, _={})

    db.refresh(reg)
    # 10 jours restants + 30 jours payés, sans perte de précision (base = current_end)
    assert reg.subscription_ends_at.date() == (now + timedelta(days=40)).date()
    # subscription_started_at préservée, pas réinitialisée
    assert reg.subscription_started_at.date() == (now - timedelta(days=100)).date()


def test_renewal_after_expiry_restarts_from_today_by_default(db, tenant):
    _cfg(db, trial_included=False)
    now = now_local()
    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(
        tenant_id=tenant.id, name="Caisse", device_id="dev1", warehouse_id=wh.id,
        subscription_started_at=now - timedelta(days=100),
        subscription_ends_at=now - timedelta(days=15),  # expirée depuis 15 jours
    )
    db.add(reg)
    payment = _payment_for(db, tenant, reg)

    confirm_payment(payment.id, ConfirmPaymentPayload(), db=db, _={})

    db.refresh(reg)
    assert reg.subscription_ends_at.date() == (now + timedelta(days=30)).date()


def test_first_payment_with_trial_included_starts_from_register_creation(db, tenant):
    _cfg(db, trial_included=True)
    now = now_local()
    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(
        tenant_id=tenant.id, name="Caisse", device_id="dev1", warehouse_id=wh.id,
        trial_ends_at=now - timedelta(days=5),  # essai expiré il y a 5 jours
    )
    reg.created_at = now - timedelta(days=20)
    db.add(reg)
    payment = _payment_for(db, tenant, reg)

    confirm_payment(payment.id, ConfirmPaymentPayload(), db=db, _={})

    db.refresh(reg)
    # part de created_at (20j avant aujourd'hui) + 30 jours payés = expire dans 10 jours
    assert reg.subscription_ends_at.date() == (now - timedelta(days=20) + timedelta(days=30)).date()
    # subscription_started_at = date du paiement (aujourd'hui), pas la date de
    # création remontée — celle-ci ne sert qu'à ancrer le calcul d'expiration,
    # même règle que _activate_tenant pour le tenant.
    assert reg.subscription_started_at.date() == now.date()


def test_first_payment_with_trial_included_falls_back_to_today_if_register_too_old(db, tenant):
    """La caisse a plus de `days` jours — repli sur aujourd'hui pour ne pas
    générer une date déjà expirée (même garde-fou que _activate_tenant)."""
    _cfg(db, trial_included=True)
    now = now_local()
    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(
        tenant_id=tenant.id, name="Caisse", device_id="dev1", warehouse_id=wh.id,
    )
    reg.created_at = now - timedelta(days=200)
    db.add(reg)
    payment = _payment_for(db, tenant, reg)

    confirm_payment(payment.id, ConfirmPaymentPayload(), db=db, _={})

    db.refresh(reg)
    assert reg.subscription_ends_at.date() == (now + timedelta(days=30)).date()


def test_first_payment_without_trial_included_starts_from_today(db, tenant):
    _cfg(db, trial_included=False)
    now = now_local()
    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(
        tenant_id=tenant.id, name="Caisse", device_id="dev1", warehouse_id=wh.id,
    )
    reg.created_at = now - timedelta(days=20)
    db.add(reg)
    payment = _payment_for(db, tenant, reg)

    confirm_payment(payment.id, ConfirmPaymentPayload(), db=db, _={})

    db.refresh(reg)
    assert reg.subscription_ends_at.date() == (now + timedelta(days=30)).date()
