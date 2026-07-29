"""Audit de sécurité suite au bug config.py::_wh_id (cross-tenant app_config) :
mêmes points d'entrée trouvés dans restaurant.py (create_table, create_menu_item,
update_menu_item) et cashier_sessions.py (_get_or_create_register) — un
warehouse_id fourni par le client était utilisé tel quel, sans vérifier qu'il
appartenait bien au tenant de l'utilisateur authentifié.
"""
from fastapi import BackgroundTasks
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.User import User
from api.models.RestaurantTable import RestaurantTable
from api.models.RoomAttribute import RoomAttribute  # noqa: F401 — requis par RestaurantTable.attributes
from api.models.MenuItem import MenuItem


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def two_tenants(db):
    t_a = Tenant(business_name="A", owner_email="a@a.com", slug="tenant-a")
    t_b = Tenant(business_name="B", owner_email="b@b.com", slug="tenant-b")
    db.add_all([t_a, t_b])
    db.flush()

    wh_a = Warehouse(tenant_id=t_a.id, name="Dépôt A", is_default=True, is_active=True)
    wh_b = Warehouse(tenant_id=t_b.id, name="Dépôt B", is_default=True, is_active=True)
    db.add_all([wh_a, wh_b])
    db.flush()

    user_a = User(
        tenant_id=t_a.id, fname="U", lname="A", username="ua",
        password="x", roles=["admin"], warehouse_id=None,
    )
    db.add(user_a)
    db.flush()
    return t_a, t_b, wh_a, wh_b, user_a


def test_create_table_rejects_foreign_warehouse(db, two_tenants):
    from api.routes.restaurant import create_table, TableCreate

    _t_a, _t_b, wh_a, wh_b, user_a = two_tenants
    data = TableCreate(name="Table 1", warehouse_id=wh_b.id)
    result = create_table(data, BackgroundTasks(), db, user_a)
    table = db.query(RestaurantTable).filter_by(id=result["id"]).first()
    assert table.warehouse_id != wh_b.id
    assert table.warehouse_id == wh_a.id  # repli sur le dépôt par défaut du tenant


def test_create_table_accepts_own_warehouse(db, two_tenants):
    from api.routes.restaurant import create_table, TableCreate

    _t_a, _t_b, wh_a, _wh_b, user_a = two_tenants
    data = TableCreate(name="Table 2", warehouse_id=wh_a.id)
    result = create_table(data, BackgroundTasks(), db, user_a)
    table = db.query(RestaurantTable).filter_by(id=result["id"]).first()
    assert table.warehouse_id == wh_a.id


def test_create_menu_item_rejects_foreign_warehouse(db, two_tenants):
    from api.routes.restaurant import create_menu_item, MenuItemCreate

    _t_a, _t_b, wh_a, wh_b, user_a = two_tenants
    data = MenuItemCreate(name="Plat", warehouse_id=wh_b.id)
    result = create_menu_item(data, db, user_a)
    item = db.query(MenuItem).filter_by(id=result["id"]).first()
    assert item.warehouse_id != wh_b.id
    assert item.warehouse_id == wh_a.id


def test_update_menu_item_rejects_foreign_warehouse(db, two_tenants):
    from api.routes.restaurant import create_menu_item, update_menu_item, MenuItemCreate, MenuItemUpdate

    _t_a, _t_b, wh_a, wh_b, user_a = two_tenants
    created = create_menu_item(MenuItemCreate(name="Plat", warehouse_id=wh_a.id), db, user_a)
    update_menu_item(created["id"], MenuItemUpdate(warehouse_id=wh_b.id), db, user_a)
    item = db.query(MenuItem).filter_by(id=created["id"]).first()
    # Rejeté — reste sur son warehouse_id d'origine (celui du tenant)
    assert item.warehouse_id == wh_a.id


def test_create_client_sabotage_rejects_foreign_warehouse(db, two_tenants):
    from api.routes.client_sabotage import create_client, ClientSabotageCreate
    from api.models.ClientSabotage import ClientSabotage

    _t_a, _t_b, wh_a, wh_b, user_a = two_tenants
    data = ClientSabotageCreate(
        nom="Jean", prenom="Pierre", telephone="50900000000",
        adresse="Rue Test", warehouse_id=wh_b.id,
    )
    result = create_client(data, BackgroundTasks(), db, user_a)
    client = db.query(ClientSabotage).filter_by(id=result.id).first()
    assert client.warehouse_id != wh_b.id
    assert client.warehouse_id == wh_a.id


def test_get_or_create_register_rejects_foreign_warehouse(db, two_tenants):
    from datetime import datetime
    from api.routes.cashier_sessions import _get_or_create_register
    from api.models.PosRegister import PosRegister
    from api.models.CashierSession import CashierSession

    t_a, _t_b, wh_a, wh_b, user_a = two_tenants

    # Un registre non-dédié existant, mais avec une session déjà ouverte —
    # aucun slot libre, force=True doit donc en créer un nouveau (branche 4).
    existing_reg = PosRegister(tenant_id=t_a.id, device_id="device-0", name="Caisse 0")
    db.add(existing_reg)
    db.flush()
    db.add(CashierSession(
        tenant_id=t_a.id, register_id=existing_reg.id, cashier_id=user_a.id,
        status="open", opened_at=datetime.now(),
    ))
    db.commit()

    reg = _get_or_create_register(
        db, t_a.id, "device-1", "Caisse 1",
        force=True, warehouse_id=wh_b.id,
        is_admin=True, user_id=user_a.id,
    )
    assert not isinstance(reg, dict)
    assert reg.warehouse_id != wh_b.id
