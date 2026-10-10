"""Un client créé hors-ligne doit recevoir le MÊME id que celui généré par
l'app (client_id) — sinon une vente créée dans la foulée (avant toute
synchro), qui référence cet id local, devient définitivement invalide dès
que la création du client synchronise sous un id serveur différent : erreur
de clé étrangère permanente, vente perdue (voir incident du 2026-09-19).
Même mécanisme que Sale.client_id (create_sale)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
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


@pytest.fixture()
def warehouse(db, tenant):
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    return wh


def test_client_id_becomes_the_customer_id(db, tenant, warehouse):
    client_id = "92aa18de-c20a-491c-829a-1090939de24a"
    data = CustomerCreate(
        name="Client", phone="50900000000", address="Rue", client_id=client_id, warehouse_id=warehouse.id,
    )

    customer = CustomerService(db, tenant_id=tenant.id).create(data)

    assert customer.id == client_id


def test_retry_with_same_client_id_is_idempotent(db, tenant, warehouse):
    """Rejeu de la même création (ex: réponse perdue côté réseau, la file
    hors-ligne retente) — doit renvoyer le client déjà créé, pas planter ni
    en créer un second."""
    client_id = "92aa18de-c20a-491c-829a-1090939de24a"
    data = CustomerCreate(
        name="Client", phone="50900000000", address="Rue", client_id=client_id, warehouse_id=warehouse.id,
    )
    service = CustomerService(db, tenant_id=tenant.id)

    first = service.create(data)
    second = service.create(data)

    assert first.id == second.id == client_id
    assert len(service.list()) == 1


def test_no_client_id_generates_a_random_id(db, tenant, warehouse):
    """Création en ligne classique (pas de client_id fourni) — inchangé :
    l'id auto-généré du modèle s'applique."""
    data = CustomerCreate(name="Client", phone="50900000000", address="Rue", warehouse_id=warehouse.id)

    customer = CustomerService(db, tenant_id=tenant.id).create(data)

    assert customer.id is not None and customer.id != ""


def test_malformed_client_id_is_ignored(db, tenant, warehouse):
    """Une string qui n'est pas un UUID valide ne doit jamais être utilisée
    comme id — repli silencieux sur l'id auto-généré."""
    data = CustomerCreate(
        name="Client", phone="50900000000", address="Rue", client_id="not-a-uuid", warehouse_id=warehouse.id,
    )

    customer = CustomerService(db, tenant_id=tenant.id).create(data)

    assert customer.id != "not-a-uuid"
