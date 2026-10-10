"""Bug corrigé : CustomerService.list() ignorait complètement le paramètre
search — GET /api/customers/?search=... renvoyait systématiquement TOUS les
clients du tenant, quel que soit le terme tapé. Le sélecteur de client
(caisse/proforma/facture, CustomerPickerField) envoie pourtant déjà ce
paramètre au serveur (corrigé côté Flutter en 2026-09, jamais implémenté
côté backend) — d'où un filtre de recherche qui ne filtrait rien."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Customer import Customer
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


@pytest.fixture()
def customers(db, tenant):
    db.add_all([
        Customer(tenant_id=tenant.id, fname="Pierre", name="Louis", phone="50912340000", address=""),
        Customer(tenant_id=tenant.id, fname="Marie", name="Joseph", phone="50956780000", address=""),
        Customer(tenant_id=tenant.id, fname="Jean", name="Pierre", phone="50999990000", address=""),
    ])
    db.commit()


def test_no_search_returns_everything(db, tenant, customers):
    """Comportement historique inchangé pour l'écran Clients (sans pagination)."""
    assert len(CustomerService(db, tenant_id=tenant.id).list()) == 3


def test_search_matches_first_name(db, tenant, customers):
    result = CustomerService(db, tenant_id=tenant.id).list(search="Pierre")
    names = {c.full_name for c in result}
    assert names == {"Pierre Louis", "Jean Pierre"}


def test_search_matches_last_name(db, tenant, customers):
    result = CustomerService(db, tenant_id=tenant.id).list(search="Joseph")
    assert [c.full_name for c in result] == ["Marie Joseph"]


def test_search_matches_phone(db, tenant, customers):
    result = CustomerService(db, tenant_id=tenant.id).list(search="9999")
    assert [c.full_name for c in result] == ["Jean Pierre"]


def test_search_is_case_insensitive(db, tenant, customers):
    result = CustomerService(db, tenant_id=tenant.id).list(search="pierre")
    assert len(result) == 2


def test_search_no_match_returns_empty(db, tenant, customers):
    assert CustomerService(db, tenant_id=tenant.id).list(search="Introuvable") == []
