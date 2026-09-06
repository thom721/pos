"""Sections Dépenses/Payroll/Prêts de la page Rapports — voir
api/routes/reports.py (expenses_report/payroll_report/loans_report).
Chaque section est activable indépendamment par tenant via
AppConfig.expenses_reports_enabled/payroll_reports_enabled/
loans_reports_enabled, vérifié côté serveur (pas seulement masqué côté
client) — voir _require_report_section."""
from datetime import date, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
from api.database import Base
from api.models.AppConfig import AppConfig
from api.models.EmployeeLoan import EmployeeLoan
from api.models.Expense import Expense
from api.models.PayrollEntry import PayrollEntry
from api.models.PayrollPeriod import PayrollPeriod
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.routes import reports


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
    u = User(tenant_id=tenant.id, fname="A", lname="B", username="ab",
             password="x", roles=["manager"], permissions=[], is_active=True)
    db.add(u)
    db.commit()
    return u


def _enable(db, tenant, **flags):
    cfg = db.query(AppConfig).filter_by(tenant_id=tenant.id, warehouse_id=None).first()
    if not cfg:
        cfg = AppConfig(tenant_id=tenant.id)
        db.add(cfg)
    for k, v in flags.items():
        setattr(cfg, k, v)
    db.commit()


def test_expenses_report_disabled_by_default_is_actually_enabled(db, tenant, user):
    """expenses_reports_enabled default=True (dépense = fonctionnalité de base,
    contrairement à payroll/prêts qui sont opt-in)."""
    result = reports.expenses_report(db=db, current_user=user, date_from=None, date_to=None, warehouse_id=None)
    assert result["global"]["total_amount"] == 0


def test_expenses_report_aggregates_by_category_and_warehouse(db, tenant, user):
    wh = Warehouse(tenant_id=tenant.id, name="Depot 1", is_default=True)
    db.add(wh)
    db.commit()

    db.add_all([
        Expense(tenant_id=tenant.id, description="Loyer", category="loyer", amount=1000,
                expense_date=now_local(), warehouse_id=wh.id),
        Expense(tenant_id=tenant.id, description="Essence", category="transport", amount=200,
                expense_date=now_local(), warehouse_id=None),
        Expense(tenant_id=tenant.id, description="Loyer 2", category="loyer", amount=500,
                expense_date=now_local(), warehouse_id=wh.id),
    ])
    db.commit()

    result = reports.expenses_report(db=db, current_user=user, date_from=None, date_to=None, warehouse_id=None)
    assert result["global"]["total_amount"] == 1700
    assert result["global"]["count"] == 3

    cats = {c["category"]: c["total_amount"] for c in result["by_category"]}
    assert cats["loyer"] == 1500
    assert cats["transport"] == 200

    whs = {w["warehouse_name"]: w["total_amount"] for w in result["by_warehouse"]}
    assert whs["Depot 1"] == 1500
    assert whs["Aucun dépôt en particulier"] == 200


def test_expenses_report_filtered_by_warehouse_omits_warehouse_breakdown(db, tenant, user):
    wh = Warehouse(tenant_id=tenant.id, name="Depot 1", is_default=True)
    db.add(wh)
    db.commit()
    db.add(Expense(tenant_id=tenant.id, description="X", amount=100,
                    expense_date=now_local(), warehouse_id=wh.id))
    db.commit()

    result = reports.expenses_report(db=db, current_user=user, date_from=None, date_to=None, warehouse_id=wh.id)
    assert result["global"]["total_amount"] == 100
    assert result["by_warehouse"] == []


def test_payroll_report_disabled_by_default(db, tenant, user):
    with pytest.raises(HTTPException) as exc:
        reports.payroll_report(db=db, current_user=user, date_from=None, date_to=None)
    assert exc.value.status_code == 403


def test_payroll_report_aggregates_when_enabled(db, tenant, user):
    _enable(db, tenant, payroll_reports_enabled=True)

    period = PayrollPeriod(
        tenant_id=tenant.id, reference="PAY-001", label="Juin 2026",
        period_start=date(2026, 6, 1), period_end=date(2026, 6, 30), pay_date=date(2026, 6, 30),
        status="paid", total_gross=5000, total_deductions=500, total_net=4500,
    )
    db.add(period)
    db.flush()
    db.add(PayrollEntry(
        tenant_id=tenant.id, period_id=period.id, employee_id=user.id,
        base_salary=5000, gross_salary=5000, net_salary=4500,
    ))
    db.commit()

    result = reports.payroll_report(db=db, current_user=user, date_from=None, date_to=None)
    assert result["global"]["total_gross"] == 5000
    assert result["global"]["total_net"] == 4500
    assert result["global"]["periods_count"] == 1
    assert result["global"]["employees_count"] == 1
    assert result["by_period"][0]["label"] == "Juin 2026"


def test_payroll_report_filtered_by_pay_date(db, tenant, user):
    _enable(db, tenant, payroll_reports_enabled=True)

    db.add(PayrollPeriod(
        tenant_id=tenant.id, reference="PAY-OLD", label="Janvier 2026",
        period_start=date(2026, 1, 1), period_end=date(2026, 1, 31), pay_date=date(2026, 1, 31),
        status="paid", total_gross=1000, total_deductions=0, total_net=1000,
    ))
    db.add(PayrollPeriod(
        tenant_id=tenant.id, reference="PAY-NEW", label="Juin 2026",
        period_start=date(2026, 6, 1), period_end=date(2026, 6, 30), pay_date=date(2026, 6, 30),
        status="paid", total_gross=2000, total_deductions=0, total_net=2000,
    ))
    db.commit()

    from datetime import datetime as dt
    result = reports.payroll_report(db=db, current_user=user, date_from=dt(2026, 3, 1), date_to=None)
    assert result["global"]["periods_count"] == 1
    assert result["global"]["total_gross"] == 2000


def test_payroll_report_excludes_unpaid_and_cancelled_periods(db, tenant, user):
    """draft/processing n'ont encore rien déboursé (les déductions de prêt ne
    s'appliquent qu'au paiement — voir payroll_service.pay_period) et
    cancelled ne le fera jamais : aucune des deux ne doit gonfler le total
    d'un rapport de dépenses réelles."""
    _enable(db, tenant, payroll_reports_enabled=True)

    db.add(PayrollPeriod(
        tenant_id=tenant.id, reference="PAY-DRAFT", label="Draft",
        period_start=date(2026, 6, 1), period_end=date(2026, 6, 30), pay_date=date(2026, 6, 30),
        status="draft", total_gross=1000, total_deductions=0, total_net=1000,
    ))
    db.add(PayrollPeriod(
        tenant_id=tenant.id, reference="PAY-PROC", label="Processing",
        period_start=date(2026, 6, 1), period_end=date(2026, 6, 30), pay_date=date(2026, 6, 30),
        status="processing", total_gross=2000, total_deductions=0, total_net=2000,
    ))
    db.add(PayrollPeriod(
        tenant_id=tenant.id, reference="PAY-CANC", label="Cancelled",
        period_start=date(2026, 6, 1), period_end=date(2026, 6, 30), pay_date=date(2026, 6, 30),
        status="cancelled", total_gross=3000, total_deductions=0, total_net=3000,
    ))
    db.add(PayrollPeriod(
        tenant_id=tenant.id, reference="PAY-PAID", label="Paid",
        period_start=date(2026, 6, 1), period_end=date(2026, 6, 30), pay_date=date(2026, 6, 30),
        status="paid", total_gross=500, total_deductions=0, total_net=500,
    ))
    db.commit()

    result = reports.payroll_report(db=db, current_user=user, date_from=None, date_to=None)
    assert result["global"]["periods_count"] == 1
    assert result["global"]["total_gross"] == 500
    assert result["by_period"][0]["label"] == "Paid"


def test_loans_report_disabled_by_default(db, tenant, user):
    with pytest.raises(HTTPException) as exc:
        reports.loans_report(db=db, current_user=user, date_from=None, date_to=None, status=None)
    assert exc.value.status_code == 403


def test_loans_report_aggregates_when_enabled(db, tenant, user):
    _enable(db, tenant, loans_reports_enabled=True)

    db.add(EmployeeLoan(
        tenant_id=tenant.id, reference="LOAN-1", employee_id=user.id,
        total_amount=1000, balance=400, monthly_deduction=200, status="active",
    ))
    db.add(EmployeeLoan(
        tenant_id=tenant.id, reference="LOAN-2", employee_id=user.id,
        total_amount=500, balance=0, monthly_deduction=100, status="paid",
    ))
    db.commit()

    result = reports.loans_report(db=db, current_user=user, date_from=None, date_to=None, status=None)
    assert result["global"]["total_amount"] == 1500
    assert result["global"]["total_balance"] == 400
    assert result["global"]["total_repaid"] == 1100
    assert result["global"]["count"] == 2

    by_status = {s["status"]: s["count"] for s in result["by_status"]}
    assert by_status["active"] == 1
    assert by_status["paid"] == 1


def test_loans_report_filtered_by_status(db, tenant, user):
    _enable(db, tenant, loans_reports_enabled=True)
    db.add(EmployeeLoan(
        tenant_id=tenant.id, reference="LOAN-1", employee_id=user.id,
        total_amount=1000, balance=400, monthly_deduction=200, status="active",
    ))
    db.add(EmployeeLoan(
        tenant_id=tenant.id, reference="LOAN-2", employee_id=user.id,
        total_amount=500, balance=0, monthly_deduction=100, status="paid",
    ))
    db.commit()

    result = reports.loans_report(db=db, current_user=user, date_from=None, date_to=None, status="active")
    assert result["global"]["count"] == 1
    assert result["global"]["total_amount"] == 1000
