"""Customer.warehouse_id : un nouveau client est rattaché à un dépôt précis
(obligatoire à la création, même convention que ProductCreate.warehouse_id).
Les clients déjà existants (warehouse_id NULL) restent partagés entre tous
les dépôts du tenant — même convention NULL-ou-dépôt que Discount."""
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Customer import Customer
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
def two_depots(db, tenant):
    a = Warehouse(tenant_id=tenant.id, name="Dépôt A", is_active=True, is_default=True)
    b = Warehouse(tenant_id=tenant.id, name="Dépôt B", is_active=True)
    db.add_all([a, b])
    db.flush()
    return a, b


def test_warehouse_id_is_required_at_creation():
    with pytest.raises(Exception):
        CustomerCreate(name="Client", phone="1", address="A")  # warehouse_id manquant


def test_unknown_warehouse_is_rejected(db, tenant):
    with pytest.raises(HTTPException) as exc:
        CustomerService(db, tenant_id=tenant.id).create(
            CustomerCreate(name="Client", phone="1", address="A", warehouse_id="introuvable")
        )
    assert exc.value.status_code == 400


def test_list_without_warehouse_filter_returns_everything(db, tenant, two_depots):
    """Comportement historique inchangé pour l'écran Clients (pas de pagination)."""
    depot_a, depot_b = two_depots
    service = CustomerService(db, tenant_id=tenant.id)
    service.create(CustomerCreate(name="A", phone="1", address="x", warehouse_id=depot_a.id))
    service.create(CustomerCreate(name="B", phone="2", address="x", warehouse_id=depot_b.id))
    db.add(Customer(tenant_id=tenant.id, name="Legacy", phone="3", address="x"))  # warehouse_id NULL
    db.commit()

    assert len(service.list()) == 3


def test_list_with_warehouse_filter_includes_own_depot_and_shared(db, tenant, two_depots):
    depot_a, depot_b = two_depots
    service = CustomerService(db, tenant_id=tenant.id)
    service.create(CustomerCreate(name="A", phone="1", address="x", warehouse_id=depot_a.id))
    service.create(CustomerCreate(name="B", phone="2", address="x", warehouse_id=depot_b.id))
    db.add(Customer(tenant_id=tenant.id, name="Legacy", phone="3", address="x"))  # NULL = partagé
    db.commit()

    names = {c.name for c in service.list(warehouse_id=depot_a.id)}
    assert names == {"A", "Legacy"}, "doit inclure le dépôt A et le client partagé, pas le dépôt B"


def test_update_can_reassign_warehouse(db, tenant, two_depots):
    depot_a, depot_b = two_depots
    service = CustomerService(db, tenant_id=tenant.id)
    created = service.create(CustomerCreate(name="A", phone="1", address="x", warehouse_id=depot_a.id))

    from api.schemas.customer import CustomerUpdate
    updated = service.update(created.id, CustomerUpdate(warehouse_id=depot_b.id))

    assert updated.warehouse_id == depot_b.id
