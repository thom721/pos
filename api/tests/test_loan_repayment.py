"""Remboursement manuel d'un prêt employé (api/services/employee_service.py
repay_loan/list_repayments) — pour le cas où le payroll n'est pas utilisé
dans le système. Réduit EmployeeLoan.balance exactement comme la déduction
automatique appliquée au paiement d'une période payroll
(payroll_service.pay_period), et passe le prêt à "paid" une fois soldé."""
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.EmployeeLoan import EmployeeLoan
from api.models.Tenant import Tenant
from api.models.User import User
from api.schemas.employee import LoanRepaymentCreate
from api.services import employee_service


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
def manager(db, tenant):
    u = User(tenant_id=tenant.id, fname="A", lname="B", username="ab",
             password="x", roles=["manager"], permissions=[], is_active=True)
    db.add(u)
    db.commit()
    return u


@pytest.fixture()
def employee(db, tenant):
    u = User(tenant_id=tenant.id, fname="C", lname="D", username="cd",
             password="x", roles=["cashier"], permissions=[], is_active=True)
    db.add(u)
    db.commit()
    return u


@pytest.fixture()
def loan(db, tenant, employee):
    l = EmployeeLoan(
        tenant_id=tenant.id, reference="LOAN-1", employee_id=employee.id,
        total_amount=1000, balance=1000, monthly_deduction=200, status="active",
    )
    db.add(l)
    db.commit()
    return l


def test_repay_loan_reduces_balance(db, tenant, manager, loan):
    result = employee_service.repay_loan(
        db, loan.id, LoanRepaymentCreate(amount=300, method="cash"),
        created_by=manager.id, tenant_id=tenant.id,
    )
    assert float(result.balance) == 700
    assert result.status == "active"


def test_repay_loan_marks_paid_when_balance_reaches_zero(db, tenant, manager, loan):
    result = employee_service.repay_loan(
        db, loan.id, LoanRepaymentCreate(amount=1000, method="moncash"),
        created_by=manager.id, tenant_id=tenant.id,
    )
    assert float(result.balance) == 0
    assert result.status == "paid"


def test_repay_loan_rejects_amount_above_balance(db, tenant, manager, loan):
    with pytest.raises(HTTPException) as exc:
        employee_service.repay_loan(
            db, loan.id, LoanRepaymentCreate(amount=1500),
            created_by=manager.id, tenant_id=tenant.id,
        )
    assert exc.value.status_code == 400


def test_repay_loan_rejects_zero_or_negative_amount(db, tenant, manager, loan):
    with pytest.raises(HTTPException) as exc:
        employee_service.repay_loan(
            db, loan.id, LoanRepaymentCreate(amount=0),
            created_by=manager.id, tenant_id=tenant.id,
        )
    assert exc.value.status_code == 400


def test_repay_loan_rejects_non_active_loan(db, tenant, manager, loan):
    loan.status = "cancelled"
    db.commit()
    with pytest.raises(HTTPException) as exc:
        employee_service.repay_loan(
            db, loan.id, LoanRepaymentCreate(amount=100),
            created_by=manager.id, tenant_id=tenant.id,
        )
    assert exc.value.status_code == 400


def test_list_repayments_returns_history_with_creator_name(db, tenant, manager, loan):
    employee_service.repay_loan(
        db, loan.id, LoanRepaymentCreate(amount=300, method="cash", note="Premier versement"),
        created_by=manager.id, tenant_id=tenant.id,
    )
    employee_service.repay_loan(
        db, loan.id, LoanRepaymentCreate(amount=200, method="natcash"),
        created_by=manager.id, tenant_id=tenant.id,
    )

    history = employee_service.list_repayments(db, loan.id, tenant_id=tenant.id)
    assert len(history) == 2
    assert float(history[0].amount) == 200  # plus récent d'abord
    assert history[1].note == "Premier versement"
    assert history[0].creator_name == "A B"


def test_repay_loan_scoped_to_tenant(db, tenant, manager, loan):
    other_tenant = Tenant(business_name="Autre", owner_email="autre@t.com", slug="autre")
    db.add(other_tenant)
    db.commit()

    with pytest.raises(HTTPException) as exc:
        employee_service.repay_loan(
            db, loan.id, LoanRepaymentCreate(amount=100),
            created_by=manager.id, tenant_id=other_tenant.id,
        )
    assert exc.value.status_code == 404
