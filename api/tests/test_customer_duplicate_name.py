"""Aucune contrainte d'unicité nom+prénom n'existe en base (des doublons
peuvent exister légitimement — vrais homonymes). Le serveur avertit avant
de créer un doublon (409) sauf si confirm_duplicate=True — ce flag est
TOUJOURS vrai pour un item rejoué depuis la file hors-ligne (aucune
confirmation interactive possible en arrière-plan), donc ce garde-fou ne
doit jamais bloquer indéfiniment une synchro (voir l'incident du
2026-09-19 : session ouverte 10 jours, ventes bloquées pour la même
classe de raison)."""
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.schemas.customer import CustomerCreate
from api.services.customer_service import CustomerService


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


def test_duplicate_name_is_rejected_without_confirmation(db, tenant):
    service = CustomerService(db, tenant_id=tenant.id)
    service.create(CustomerCreate(fname="Jean", name="Pierre", phone="1", address="A"))

    with pytest.raises(HTTPException) as exc:
        service.create(CustomerCreate(fname="Jean", name="Pierre", phone="2", address="B"))
    assert exc.value.status_code == 409
    assert exc.value.detail["duplicate"] is True


def test_duplicate_name_is_case_and_space_insensitive(db, tenant):
    service = CustomerService(db, tenant_id=tenant.id)
    service.create(CustomerCreate(fname="Jean", name="Pierre", phone="1", address="A"))

    with pytest.raises(HTTPException):
        service.create(CustomerCreate(fname="  JEAN ", name=" pierre  ", phone="2", address="B"))


def test_confirm_duplicate_allows_creation(db, tenant):
    """L'utilisateur a explicitement confirmé vouloir un doublon (vrai
    homonyme) — la création doit réussir normalement."""
    service = CustomerService(db, tenant_id=tenant.id)
    service.create(CustomerCreate(fname="Jean", name="Pierre", phone="1", address="A"))

    second = service.create(CustomerCreate(
        fname="Jean", name="Pierre", phone="2", address="B", confirm_duplicate=True,
    ))

    assert second is not None
    assert len(service.list()) == 2


def test_offline_queue_replay_is_never_blocked_by_duplicate_check(db, tenant):
    """Simule un item rejoué depuis la file hors-ligne : client_id +
    confirm_duplicate=True toujours envoyés ensemble par l'app dans ce cas
    (voir customer_repository.dart) — doit toujours réussir, jamais rester
    bloqué en attente d'une confirmation qui ne viendra jamais."""
    service = CustomerService(db, tenant_id=tenant.id)
    service.create(CustomerCreate(fname="Jean", name="Pierre", phone="1", address="A"))

    replayed = service.create(CustomerCreate(
        fname="Jean", name="Pierre", phone="2", address="B",
        client_id="11111111-1111-1111-1111-111111111111",
        confirm_duplicate=True,
    ))

    assert replayed.id == "11111111-1111-1111-1111-111111111111"


def test_different_names_never_trigger_the_duplicate_check(db, tenant):
    service = CustomerService(db, tenant_id=tenant.id)
    service.create(CustomerCreate(fname="Jean", name="Pierre", phone="1", address="A"))

    other = service.create(CustomerCreate(fname="Marie", name="Louis", phone="2", address="B"))

    assert other is not None
