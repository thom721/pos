"""Cinq entites listees dans SYNC_ENTITIES se faisaient supprimer uniquement
via une cascade ORM (cascade="all, delete-orphan") declenchee par le
db.delete() de leur parent, sans jamais passer par record_deletion() :
PayrollLoanDeduction (via PayrollEntry, reprocessing d'une periode),
ModifierOption (via ModifierGroup), RoomAttribute (via RestaurantTable,
suppression complete de la table — le remplacement d'attributs sur
update_table en avait deja un), InvoiceItem (via Invoice) et ProformaItem
(via Proforma). Sans tombstone, ces lignes orphelines ne disparaissaient
jamais de l'autre cote (cloud ou local)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.User import User
from api.models.SyncTombstone import SyncTombstone
from api.models.EmployeeProfile import EmployeeProfile
from api.models.EmployeeLoan import EmployeeLoan
from api.models.PayrollLoanDeduction import PayrollLoanDeduction
from api.models.MenuItem import MenuItem  # noqa: F401 — requis par ModifierGroup.menu_item_id
from api.models.ModifierGroup import ModifierGroup, ModifierOption
from api.models.RestaurantTable import RestaurantTable
from api.models.RoomAttribute import RoomAttribute
from api.models.Invoice import Invoice, InvoiceItem
from api.models.Proforma import Proforma, ProformaItem
from api.schemas.payroll import PayrollPeriodCreate
from api.services import payroll_service, invoice_service, proforma_service


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


def _tombstone(db, entity_type, record_id):
    return db.query(SyncTombstone).filter_by(
        entity_type=entity_type, record_id=str(record_id),
    ).first()


def test_reprocess_period_tombstones_cascaded_loan_deductions(db, tenant):
    employee = User(
        tenant_id=tenant.id, fname="E", lname="Mploy", username="emp1",
        password="x", roles=["cashier"],
    )
    db.add(employee)
    db.flush()
    profile = EmployeeProfile(
        tenant_id=tenant.id, user_id=employee.id, base_salary=1000, is_active=True,
    )
    loan = EmployeeLoan(
        tenant_id=tenant.id, reference="LOAN-1", employee_id=employee.id,
        total_amount=500, balance=500, monthly_deduction=100, status="active",
    )
    db.add_all([profile, loan])
    db.commit()

    period = payroll_service.create_period(
        db, PayrollPeriodCreate(
            label="Octobre", period_start="2026-10-01", period_end="2026-10-31",
            pay_date="2026-11-01",
        ),
        created_by=None, tenant_id=tenant.id,
    )
    payroll_service.process_period(db, period.id, tenant_id=tenant.id)
    deduction_id = db.query(PayrollLoanDeduction).filter_by(loan_id=loan.id).first().id

    # Re-traiter la meme periode : supprime les anciennes entries (et, en
    # cascade, leurs loan_deductions) avant d'en recreer.
    payroll_service.process_period(db, period.id, tenant_id=tenant.id)

    assert _tombstone(db, "payroll_loan_deduction", deduction_id) is not None


def test_delete_modifier_group_tombstones_options(db, tenant):
    from api.routes.restaurant import delete_modifier_group

    admin = User(tenant_id=tenant.id, fname="A", lname="Dmin", username="adm1",
                 password="x", roles=["admin"])
    db.add(admin)
    db.flush()
    group = ModifierGroup(tenant_id=tenant.id, name="Taille")
    db.add(group)
    db.flush()
    option = ModifierOption(tenant_id=tenant.id, group_id=group.id, name="Grand", extra_price=0)
    db.add(option)
    db.commit()
    option_id = option.id

    delete_modifier_group(group.id, db, admin)

    assert db.query(ModifierOption).filter_by(id=option_id).first() is None
    assert _tombstone(db, "modifier_option", option_id) is not None


def test_delete_table_tombstones_room_attributes(db, tenant):
    from api.routes.restaurant import delete_table

    admin = User(tenant_id=tenant.id, fname="A", lname="Dmin", username="adm2",
                 password="x", roles=["admin"])
    db.add(admin)
    db.flush()
    table = RestaurantTable(tenant_id=tenant.id, name="Table 1")
    db.add(table)
    db.flush()
    attr = RoomAttribute(tenant_id=tenant.id, table_id=table.id, key="vue", value="mer")
    db.add(attr)
    db.commit()
    attr_id = attr.id

    delete_table(table.id, db, admin)

    assert db.query(RoomAttribute).filter_by(id=attr_id).first() is None
    assert _tombstone(db, "room_attribute", attr_id) is not None


def test_delete_invoice_tombstones_items(db, tenant):
    from api.core.dt_coerce import now_local

    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    invoice = Invoice(tenant_id=tenant.id, warehouse_id=wh.id, reference="INV-1",
                       date=now_local(), client_name="Client", discount=0, paid_amount=0)
    db.add(invoice)
    db.flush()
    item = InvoiceItem(tenant_id=tenant.id, warehouse_id=wh.id, invoice_id=invoice.id,
                        name="Service", quantity=1, unit_price=100, subtotal=100)
    db.add(item)
    db.commit()
    item_id, invoice_id = item.id, invoice.id

    invoice_service.delete_invoice(db, invoice_id, tenant_id=tenant.id)

    assert db.query(InvoiceItem).filter_by(id=item_id).first() is None
    assert _tombstone(db, "invoice_item", item_id) is not None


def test_delete_proforma_tombstones_items(db, tenant):
    from api.core.dt_coerce import now_local

    wh = Warehouse(tenant_id=tenant.id, name="Depot", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    proforma = Proforma(tenant_id=tenant.id, warehouse_id=wh.id, reference="PRO-1",
                         date=now_local(), client_name="Client", discount=0)
    db.add(proforma)
    db.flush()
    item = ProformaItem(tenant_id=tenant.id, warehouse_id=wh.id, proforma_id=proforma.id,
                         name="Service", quantity=1, unit_price=100, subtotal=100)
    db.add(item)
    db.commit()
    item_id, proforma_id = item.id, proforma.id

    proforma_service.delete_proforma(db, proforma_id, tenant_id=tenant.id)

    assert db.query(ProformaItem).filter_by(id=item_id).first() is None
    assert _tombstone(db, "proforma_item", item_id) is not None
