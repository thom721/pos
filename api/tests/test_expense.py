"""CRUD des dépenses (charges d'exploitation) — voir api/services/expense_service.py,
api/models/Expense.py. Permission expenses.* accordée au rôle manager
(api/core/permissions.py). Teste la couche service directement (le routeur
FastAPI n'ajoute que l'auth/permission, déjà couvertes ailleurs)."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
from api.database import Base
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.schemas.expense import ExpenseCreate, ExpenseUpdate
from api.services import expense_service


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
def other_tenant(db):
    t = Tenant(business_name="Autre", owner_email="autre@t.com", slug="autre")
    db.add(t)
    db.flush()
    return t


@pytest.fixture()
def user(db, tenant):
    u = User(tenant_id=tenant.id, fname="A", lname="B", username="ab",
             password="x", roles=["manager"], permissions=[], is_active=True)
    db.add(u)
    db.commit()
    return u


def test_create_and_list_expense(db, tenant, user):
    created = expense_service.create_expense(
        db, ExpenseCreate(description="Loyer local", category="loyer", amount=5000),
        tenant_id=tenant.id, user_id=user.id,
    )
    assert created["description"] == "Loyer local"
    assert created["category"] == "loyer"
    assert created["amount"] == 5000
    assert created["user_name"] == "A B"
    assert created["warehouse_id"] is None

    result = expense_service.list_expenses(db, tenant_id=tenant.id)
    assert result["meta"].total == 1
    assert result["data"][0]["description"] == "Loyer local"


def test_expense_scoped_to_warehouse(db, tenant, user):
    wh = Warehouse(tenant_id=tenant.id, name="Depot 1", is_default=True)
    db.add(wh)
    db.commit()

    created = expense_service.create_expense(
        db, ExpenseCreate(description="Transport", amount=200, warehouse_id=wh.id),
        tenant_id=tenant.id, user_id=user.id,
    )
    assert created["warehouse_id"] == wh.id
    assert created["warehouse_name"] == "Depot 1"

    result = expense_service.list_expenses(db, tenant_id=tenant.id, warehouse_id=wh.id)
    assert result["meta"].total == 1

    other = expense_service.list_expenses(db, tenant_id=tenant.id, warehouse_id="autre-id")
    assert other["meta"].total == 0


def test_expense_isolated_per_tenant(db, tenant, other_tenant, user):
    other_user = User(tenant_id=other_tenant.id, fname="C", lname="D", username="cd",
                       password="x", roles=["manager"], permissions=[], is_active=True)
    db.add(other_user)
    db.commit()

    expense_service.create_expense(
        db, ExpenseCreate(description="Dépense tenant A", amount=100),
        tenant_id=tenant.id, user_id=user.id,
    )
    expense_service.create_expense(
        db, ExpenseCreate(description="Dépense tenant B", amount=200),
        tenant_id=other_tenant.id, user_id=other_user.id,
    )

    result_a = expense_service.list_expenses(db, tenant_id=tenant.id)
    assert result_a["meta"].total == 1
    assert result_a["data"][0]["description"] == "Dépense tenant A"


def test_update_and_delete_expense(db, tenant, user):
    created = expense_service.create_expense(
        db, ExpenseCreate(description="Fournitures", amount=50),
        tenant_id=tenant.id, user_id=user.id,
    )
    updated = expense_service.update_expense(
        db, created["id"], ExpenseUpdate(amount=75), tenant_id=tenant.id,
    )
    assert updated["amount"] == 75

    ok = expense_service.delete_expense(db, created["id"], tenant_id=tenant.id)
    assert ok is True
    assert expense_service.list_expenses(db, tenant_id=tenant.id)["meta"].total == 0


def test_search_and_date_filter(db, tenant, user):
    now = now_local()
    expense_service.create_expense(
        db, ExpenseCreate(description="Achat essence", amount=30, expense_date=now - timedelta(days=10)),
        tenant_id=tenant.id, user_id=user.id,
    )
    expense_service.create_expense(
        db, ExpenseCreate(description="Reparation camion", amount=300, expense_date=now),
        tenant_id=tenant.id, user_id=user.id,
    )

    by_search = expense_service.list_expenses(db, tenant_id=tenant.id, search="essence")
    assert by_search["meta"].total == 1

    by_date = expense_service.list_expenses(db, tenant_id=tenant.id, date_from=now - timedelta(days=1))
    assert by_date["meta"].total == 1
    assert by_date["data"][0]["description"] == "Reparation camion"
