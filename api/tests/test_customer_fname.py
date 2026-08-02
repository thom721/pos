"""Customer.fname : ajouté pour que l'enregistrement d'un client capture le
prénom séparément du nom (évite les conflits/confusion entre clients partageant
un nom de famille). Les clients existants gardent name=texte libre, fname vide
— aucun découpage rétroactif tenté (choix explicite)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Customer import Customer


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


def test_full_name_combines_fname_and_name(db, tenant):
    c = Customer(tenant_id=tenant.id, fname="Pierre", name="Louis", phone="50900000000", address="Rue")
    db.add(c)
    db.flush()
    assert c.full_name == "Pierre Louis"


def test_full_name_falls_back_to_name_when_fname_empty(db, tenant):
    """Client existant créé avant l'ajout de fname : full_name == name, sans
    espace parasite ni régression sur l'affichage (reçus, listes, etc.)."""
    c = Customer(tenant_id=tenant.id, name="Pierre Louis", phone="50900000000", address="Rue")
    db.add(c)
    db.flush()
    assert c.fname in (None, "")
    assert c.full_name == "Pierre Louis"
