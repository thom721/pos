"""PUT /api/warehouses/{id} doit permettre de rattacher/détacher un entrepôt
existant à un dépôt (linked_warehouse_id) — c'est le seul endroit où un
entrepôt déjà créé peut être édité après coup, puisque la création elle-même
est réservée au cloud (voir entrepot_service.create_entrepot)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.schemas.warehouse import WarehouseUpdate
from api.routes.warehouse import update_warehouse


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
def user(db, tenant):
    u = User(fname="A", lname="B", username="admin", email="a@t.com",
              password="x", tenant_id=tenant.id, roles=["admin"], permissions=[],
              is_active=True)
    db.add(u)
    db.flush()
    return u


def test_update_warehouse_links_entrepot_to_depot(db, tenant, user):
    depot = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    entrepot = Warehouse(tenant_id=tenant.id, name="Entrepôt", is_entrepot=True, is_claimed=True)
    db.add_all([depot, entrepot])
    db.commit()

    updated = update_warehouse(
        entrepot.id, WarehouseUpdate(linked_warehouse_id=depot.id),
        db=db, current_user=user,
    )
    assert updated.linked_warehouse_id == depot.id


def test_update_warehouse_unlinks_entrepot(db, tenant, user):
    depot = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(depot)
    db.flush()
    entrepot = Warehouse(tenant_id=tenant.id, name="Entrepôt", is_entrepot=True,
                          is_claimed=True, linked_warehouse_id=depot.id)
    db.add(entrepot)
    db.commit()

    updated = update_warehouse(
        entrepot.id, WarehouseUpdate(unlink_warehouse=True),
        db=db, current_user=user,
    )
    assert updated.linked_warehouse_id is None


def test_update_warehouse_rejects_linking_to_another_entrepot(db, tenant, user):
    other_entrepot = Warehouse(tenant_id=tenant.id, name="Autre entrepôt", is_entrepot=True, is_claimed=True)
    entrepot = Warehouse(tenant_id=tenant.id, name="Entrepôt", is_entrepot=True, is_claimed=True)
    db.add_all([other_entrepot, entrepot])
    db.commit()

    with pytest.raises(HTTPException) as exc:
        update_warehouse(
            entrepot.id, WarehouseUpdate(linked_warehouse_id=other_entrepot.id),
            db=db, current_user=user,
        )
    assert exc.value.status_code == 404


def test_update_regular_warehouse_ignores_link_fields(db, tenant, user):
    """Le champ linked_warehouse_id n'a de sens que pour un entrepôt — sur un
    dépôt classique (is_entrepot=False), il est silencieusement ignoré."""
    other = Warehouse(tenant_id=tenant.id, name="Autre dépôt", is_active=True)
    depot = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add_all([other, depot])
    db.commit()

    updated = update_warehouse(
        depot.id, WarehouseUpdate(linked_warehouse_id=other.id),
        db=db, current_user=user,
    )
    assert updated.linked_warehouse_id is None
