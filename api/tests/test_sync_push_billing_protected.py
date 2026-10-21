"""Bug reel : sync_push (cote cloud, /api/sync/push) ecrasait sans aucune
protection TOUT champ renvoye par un serveur local, y compris
subscription_ends_at/subscription_started_at sur PosRegister — des champs
autoritaires cote cloud uniquement, poses par confirm_payment/
_activate_tenant, jamais par un serveur local. Un push qui arrive apres la
confirmation d'un paiement (ex: un simple heartbeat qui bump updated_at
localement sans toucher l'abonnement) ecrasait silencieusement la date
fraichement confirmee avec la copie perimee (souvent None) du serveur
local. Vu en prod : paiement confirme "paye", registre retrouve avec le
bon tenant, mais subscription_ends_at reste None."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.routes.sync import sync_push, PushRequest


class _FakeRequest:
    headers: dict = {}


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


def test_push_never_overwrites_confirmed_subscription(db):
    tenant = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(tenant)
    db.flush()
    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_default=True)
    db.add(wh)
    db.flush()

    reg = PosRegister(tenant_id=tenant.id, warehouse_id=wh.id, name="caisse thom")
    # Confirmation du paiement cote cloud : date d'abonnement posee.
    confirmed_end = now_local() + timedelta(days=30)
    reg.subscription_started_at = now_local()
    reg.subscription_ends_at = confirmed_end
    db.add(reg)
    db.commit()

    # Push d'un serveur local avec une copie perimee (jamais activee,
    # updated_at plus recent — ex: un heartbeat local qui a juste touche la
    # ligne sans toucher l'abonnement).
    stale_record = {
        "id": reg.id,
        "tenant_id": tenant.id,
        "warehouse_id": wh.id,
        "name": "caisse thom",
        "device_id": None,
        "is_device_approved": True,
        "is_active": True,
        "session_token": None,
        "last_seen": None,
        "app_version": "2.0.0",
        "app_build": 71,
        "is_initial": False,
        "trial_ends_at": None,
        "subscription_started_at": None,
        "subscription_ends_at": None,
        "dedicated_user_id": None,
        "created_at": reg.created_at.isoformat(),
        "updated_at": (now_local() + timedelta(minutes=5)).isoformat(),
    }

    body = PushRequest(entity_type="pos_register", records=[stale_record])
    claims = {"tenant_id": tenant.id, "tenant_type": "shared"}

    result = sync_push(body=body, request=_FakeRequest(), claims=claims, db=db)
    assert result["ok"] is True

    db.refresh(reg)
    assert reg.subscription_ends_at is not None
    assert abs((reg.subscription_ends_at - confirmed_end).total_seconds()) < 2


def test_push_still_sets_subscription_on_brand_new_register(db):
    """Un registre tout juste cree localement (jamais vu du cloud) doit
    quand meme accepter ses valeurs initiales a l'insertion — la protection
    ne doit jouer qu'a la mise a jour d'une ligne deja existante."""
    tenant = Tenant(business_name="T2", owner_email="t2@t.com", slug="t2")
    db.add(tenant)
    db.flush()
    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_default=True)
    db.add(wh)
    db.flush()

    new_end = now_local() + timedelta(days=30)
    record = {
        "id": "44444444-4444-4444-4444-444444444444",
        "tenant_id": tenant.id,
        "warehouse_id": wh.id,
        "name": "nouvelle caisse",
        "device_id": None,
        "is_device_approved": True,
        "is_active": True,
        "session_token": None,
        "last_seen": None,
        "app_version": None,
        "app_build": None,
        "is_initial": False,
        "trial_ends_at": None,
        "subscription_started_at": now_local().isoformat(),
        "subscription_ends_at": new_end.isoformat(),
        "dedicated_user_id": None,
        "created_at": now_local().isoformat(),
        "updated_at": now_local().isoformat(),
    }

    body = PushRequest(entity_type="pos_register", records=[record])
    claims = {"tenant_id": tenant.id, "tenant_type": "shared"}

    result = sync_push(body=body, request=_FakeRequest(), claims=claims, db=db)
    assert result["ok"] is True
    assert result["inserted"] == 1

    new_reg = db.get(PosRegister, record["id"])
    assert new_reg is not None
    assert new_reg.subscription_ends_at is not None
    assert abs((new_reg.subscription_ends_at - new_end).total_seconds()) < 2
