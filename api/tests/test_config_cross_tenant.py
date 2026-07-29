"""Bug de sécurité corrigé : GET/PUT /api/config/ acceptait un warehouse_id
fourni par le client (query param) sans vérifier qu'il appartenait bien au
tenant de l'utilisateur authentifié. Un warehouse_id d'un AUTRE tenant créait
une ligne app_config cross-tenant (tenant_id correct, warehouse_id d'un
tenant étranger) — invisible côté cloud (la contrainte FK est satisfaite),
mais provoquant une erreur de contrainte FK dès qu'une installation locale
tirait cette ligne (le dépôt étranger n'existe pas dans son propre tenant).

Reproduit en production : voir _repair_cross_tenant_app_config (main.py).
"""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.User import User
from api.models.AppConfig import AppConfig
from api.routes.config import _wh_id
import api.main as m


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    session.info["engine"] = engine
    yield session
    session.close()


@pytest.fixture()
def two_tenants(db):
    t_a = Tenant(business_name="A", owner_email="a@a.com", slug="tenant-a")
    t_b = Tenant(business_name="B", owner_email="b@b.com", slug="tenant-b")
    db.add_all([t_a, t_b])
    db.flush()

    wh_a = Warehouse(tenant_id=t_a.id, name="Dépôt A", is_default=True)
    wh_b = Warehouse(tenant_id=t_b.id, name="Dépôt B", is_default=True)
    db.add_all([wh_a, wh_b])
    db.flush()

    user_a = User(
        tenant_id=t_a.id, fname="U", lname="A", username="ua",
        password="x", roles=["cashier"],
    )
    db.add(user_a)
    db.flush()
    return t_a, t_b, wh_a, wh_b, user_a


def test_wh_id_rejects_warehouse_from_another_tenant(db, two_tenants):
    _t_a, _t_b, _wh_a, wh_b, user_a = two_tenants
    # user_a (tenant A) essaie d'utiliser le dépôt de tenant B — doit être rejeté
    result = _wh_id(db, user_a, wh_b.id)
    assert result is None


def test_wh_id_accepts_warehouse_from_own_tenant(db, two_tenants):
    _t_a, _t_b, wh_a, _wh_b, user_a = two_tenants
    result = _wh_id(db, user_a, wh_a.id)
    assert result == wh_a.id


def test_repair_fixes_existing_cross_tenant_app_config(db, two_tenants):
    t_a, _t_b, _wh_a, wh_b, _user_a = two_tenants
    engine = db.info["engine"]

    # Simule la donnée corrompue produite par l'ancien bug : app_config de
    # tenant A pointant vers le warehouse de tenant B.
    corrupt = AppConfig(tenant_id=t_a.id, warehouse_id=wh_b.id, business_name="Store One")
    db.add(corrupt)
    db.commit()

    m._repair_cross_tenant_app_config(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    reloaded = fresh.query(AppConfig).filter_by(id=corrupt.id).first()
    assert reloaded.warehouse_id is None


def test_repair_leaves_correct_app_config_untouched(db, two_tenants):
    t_a, _t_b, wh_a, _wh_b, _user_a = two_tenants
    engine = db.info["engine"]

    correct = AppConfig(tenant_id=t_a.id, warehouse_id=wh_a.id, business_name="Store One")
    db.add(correct)
    db.commit()

    m._repair_cross_tenant_app_config(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    reloaded = fresh.query(AppConfig).filter_by(id=correct.id).first()
    assert reloaded.warehouse_id == wh_a.id


def test_repair_is_idempotent(db, two_tenants):
    t_a, _t_b, _wh_a, wh_b, _user_a = two_tenants
    engine = db.info["engine"]

    corrupt = AppConfig(tenant_id=t_a.id, warehouse_id=wh_b.id, business_name="Store One")
    db.add(corrupt)
    db.commit()

    m._repair_cross_tenant_app_config(active_engine=engine)
    m._repair_cross_tenant_app_config(active_engine=engine)  # deuxième passage — no-op

    Session = sessionmaker(bind=engine)
    fresh = Session()
    reloaded = fresh.query(AppConfig).filter_by(id=corrupt.id).first()
    assert reloaded.warehouse_id is None
