"""Bug rapporté : logo mis à jour côté web (config globale ou un dépôt donné)
jamais visible sur les reçus d'un appareil rattaché à un AUTRE dépôt. Cause :
AppConfig est stocké par dépôt — create_for_warehouse crée automatiquement
une ligne vide pour chaque dépôt, qui masque ensuite silencieusement tout
logo mis à jour ailleurs. Le logo doit être partagé par tout le tenant.
"""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.AppConfig import AppConfig
from api.services import config_service


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def tenant_with_two_warehouses(db):
    t = Tenant(business_name="Store One", owner_email="a@a.com", slug="store-one")
    db.add(t)
    db.flush()
    wh_a = Warehouse(tenant_id=t.id, name="Dépôt A", is_default=True)
    wh_b = Warehouse(tenant_id=t.id, name="Dépôt B")
    db.add_all([wh_a, wh_b])
    db.flush()
    return t, wh_a, wh_b


def test_logo_update_on_global_config_propagates_to_existing_warehouse_row(
    db, tenant_with_two_warehouses
):
    t, wh_a, _wh_b = tenant_with_two_warehouses
    # Dépôt A a déjà sa propre ligne AppConfig (créée automatiquement à sa
    # création), logo vide — reproduit le bug tel que rapporté.
    config_service.create_for_warehouse(db, tenant_id=t.id, warehouse_id=wh_a.id)

    config_service.update(db, {"logo_path": "/static/logos/new.png"}, tenant_id=t.id)

    per_wh = db.query(AppConfig).filter_by(tenant_id=t.id, warehouse_id=wh_a.id).first()
    assert per_wh.logo_path == "/static/logos/new.png"


def test_logo_update_on_one_warehouse_propagates_to_other_warehouse(
    db, tenant_with_two_warehouses
):
    t, wh_a, wh_b = tenant_with_two_warehouses
    config_service.create_for_warehouse(db, tenant_id=t.id, warehouse_id=wh_a.id)
    config_service.create_for_warehouse(db, tenant_id=t.id, warehouse_id=wh_b.id)

    config_service.update(
        db, {"logo_path": "/static/logos/new.png"}, tenant_id=t.id, warehouse_id=wh_a.id
    )

    other = db.query(AppConfig).filter_by(tenant_id=t.id, warehouse_id=wh_b.id).first()
    assert other.logo_path == "/static/logos/new.png"


def test_non_logo_field_stays_scoped_to_its_own_warehouse(db, tenant_with_two_warehouses):
    t, wh_a, wh_b = tenant_with_two_warehouses
    config_service.create_for_warehouse(db, tenant_id=t.id, warehouse_id=wh_a.id)
    config_service.create_for_warehouse(db, tenant_id=t.id, warehouse_id=wh_b.id)

    config_service.update(
        db, {"address": "123 Rue A"}, tenant_id=t.id, warehouse_id=wh_a.id
    )

    other = db.query(AppConfig).filter_by(tenant_id=t.id, warehouse_id=wh_b.id).first()
    assert other.address != "123 Rue A"
