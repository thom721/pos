"""Système de Sabotage — clients, dépôts, retraits (compte bancaire par client)."""
import json

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401 — enregistre tous les modèles auprès de Base.metadata
from api.database import Base
from api.models.Tenant import Tenant
from api.services import sabotage_service
import api.services.local_sync_service as local_sync_service
import api.routes.sync as sync_routes


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
    t = Tenant(business_name="Test", owner_email="t@test.com", slug="test-tenant")
    db.add(t)
    db.flush()
    return t


@pytest.fixture()
def other_tenant(db):
    t = Tenant(business_name="Autre", owner_email="autre@test.com", slug="autre-tenant")
    db.add(t)
    db.flush()
    return t


def _make_client(db, tenant_id, telephone="50912345678"):
    return sabotage_service.create_client(
        db,
        tenant_id=tenant_id,
        warehouse_id=None,
        nom="Pierre",
        prenom="Jean",
        telephone=telephone,
        adresse="Rue Test",
    )


def test_account_number_generation_retries_on_collision(db, tenant, monkeypatch):
    calls = {"n": 0}
    values = ["100000", "100000", "222222"]  # collision forcée sur les 2 premiers appels

    def fake_randbelow(_n):
        v = values[calls["n"]]
        calls["n"] += 1
        return int(v)

    # Première génération occupe "100000"
    monkeypatch.setattr(sabotage_service.secrets, "randbelow", fake_randbelow)
    first = sabotage_service.generate_account_number(db, tenant.id)
    assert first == "100000"

    client = _make_client_with_account(db, tenant.id, "100000")

    # Deuxième génération doit re-essayer car "100000" est pris, puis réussir avec "222222"
    second = sabotage_service.generate_account_number(db, tenant.id)
    assert second == "222222"
    assert calls["n"] == 3


def _make_client_with_account(db, tenant_id, account_number):
    from api.models.ClientSabotage import ClientSabotage
    c = ClientSabotage(
        tenant_id=tenant_id, warehouse_id=None,
        nom="A", prenom="B", telephone="00000000",
        adresse="x", account_number=account_number,
    )
    db.add(c)
    db.commit()
    return c


def test_telephone_unique_per_tenant_rejects_duplicate(db, tenant):
    _make_client(db, tenant.id, telephone="50911112222")
    with pytest.raises(Exception):
        _make_client(db, tenant.id, telephone="50911112222")


def test_telephone_can_repeat_across_different_tenants(db, tenant, other_tenant):
    c1 = _make_client(db, tenant.id, telephone="50933334444")
    c2 = _make_client(db, other_tenant.id, telephone="50933334444")
    assert c1.id != c2.id
    assert c1.telephone == c2.telephone


def test_record_depot_increases_balance(db, tenant):
    client = _make_client(db, tenant.id)
    assert client.balance == 0
    sabotage_service.record_depot(
        db, client_id=client.id, amount=500, tenant_id=tenant.id, warehouse_id=None,
    )
    db.refresh(client)
    assert client.balance == 500


def test_record_retrait_decreases_balance(db, tenant):
    client = _make_client(db, tenant.id)
    sabotage_service.record_depot(db, client_id=client.id, amount=500, tenant_id=tenant.id, warehouse_id=None)
    db.refresh(client)
    sabotage_service.record_retrait(db, client_id=client.id, amount=200, tenant_id=tenant.id, warehouse_id=None)
    db.refresh(client)
    assert client.balance == 300


def test_record_retrait_blocked_when_amount_exceeds_balance(db, tenant):
    client = _make_client(db, tenant.id)
    sabotage_service.record_depot(db, client_id=client.id, amount=100, tenant_id=tenant.id, warehouse_id=None)
    db.refresh(client)
    with pytest.raises(Exception):
        sabotage_service.record_retrait(db, client_id=client.id, amount=101, tenant_id=tenant.id, warehouse_id=None)
    db.refresh(client)
    assert client.balance == 100  # inchangé — le retrait n'a pas eu lieu


def test_extra_fields_json_roundtrip(db, tenant):
    client = sabotage_service.create_client(
        db,
        tenant_id=tenant.id,
        warehouse_id=None,
        nom="Marie",
        prenom="Claire",
        telephone="50955556666",
        adresse="Rue B",
        extra_fields={"profession": "Enseignante", "email": "marie@test.com"},
    )
    assert json.loads(client.extra_fields) == {"profession": "Enseignante", "email": "marie@test.com"}


def test_sync_registries_contain_sabotage_entities():
    """Non-régression du bug `discount` 400 : un seul des deux registres avait
    été mis à jour. Les deux doivent toujours contenir les nouvelles entités."""
    names = {e["type"] for e in local_sync_service.SYNC_ENTITIES}
    assert {"client_sabotage", "depot", "retrait"} <= names
    assert {"client_sabotage", "depot", "retrait"} <= sync_routes._MODEL_MAP.keys()
