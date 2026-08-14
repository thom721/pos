"""Bug corrigé (production) : _submit_register_payment_for_tenant générait
invoice_number via COUNT(...)+1 — pas atomique. Deux soumissions concurrentes
(ou un double-clic/retry après une erreur transitoire) pouvaient tomber sur
le même numéro, provoquant une IntegrityError sur la contrainte unique
invoice_number remontée au tenant comme "Erreur interne du serveur" (500).
Vu en prod : "Duplicate entry 'REG-2026-0005' for key
'billing_payments.invoice_number'". _generate_and_commit_payments retente
désormais depuis un COUNT() frais plutôt que de laisser planter la requête."""
from datetime import datetime

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.models.User import User
from api.models.BillingPayment import BillingPayment
import api.routes.billing as billing
from api.routes.billing import SubmitRegisterPaymentRequest


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def tenant_with_register(db):
    tenant = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(tenant)
    db.flush()
    wh = Warehouse(tenant_id=tenant.id, name="Depot principal", is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(tenant_id=tenant.id, name="Caisse 2", device_id="dev1", warehouse_id=wh.id)
    db.add(reg)
    user = User(
        tenant_id=tenant.id, fname="A", lname="B", username="ab",
        password="x", roles=["admin"],
    )
    db.add(user)
    db.commit()
    return tenant, wh, reg, user


def test_submit_register_payment_retries_on_invoice_number_collision(db, tenant_with_register, monkeypatch):
    tenant, _wh, reg, user = tenant_with_register
    monkeypatch.setattr(billing.settings, "BILLING_URL", "")
    monkeypatch.setattr(billing.settings, "CLOUD_SYNC_TOKEN", "")

    year = datetime.now().year
    # Une ligne existe déjà avec le numéro que le COUNT()+1 initial va générer
    # ("REG-{year}-0001" — aucune autre facture REG- pour l'instant) : simule
    # exactement la collision vue en prod (double-clic / retry concurrent).
    clashing = BillingPayment(
        tenant_id=tenant.id,
        invoice_number=f"REG-{year}-0001",
        method="cash", amount=100, currency="HTG", months=1,
        status="pending", plan_type="monthly",
    )
    db.add(clashing)
    db.commit()

    body = SubmitRegisterPaymentRequest(register_ids=[reg.id], method="cash", months=1, plan_type="monthly")
    result = billing.submit_register_payment(body, db, user)

    assert result["status"] == "pending"
    payments = db.query(BillingPayment).filter_by(tenant_id=tenant.id).all()
    assert len(payments) == 2
    numbers = {p.invoice_number for p in payments}
    assert numbers == {f"REG-{year}-0001", f"REG-{year}-0002"}


def test_generate_and_commit_payments_gives_up_after_max_attempts(db, tenant_with_register):
    """Si la collision persiste (build() régénère toujours le même numéro
    déjà pris), l'IntegrityError finit par remonter plutôt que boucler
    indéfiniment."""
    tenant, _wh, _reg, _user = tenant_with_register
    stuck = BillingPayment(
        tenant_id=tenant.id, invoice_number="REG-9999-0001",
        method="cash", amount=1, currency="HTG", months=1,
        status="pending", plan_type="monthly",
    )
    db.add(stuck)
    db.commit()

    def _build(base_count):
        p = BillingPayment(
            tenant_id=tenant.id, invoice_number="REG-9999-0001",
            method="cash", amount=1, currency="HTG", months=1,
            status="pending", plan_type="monthly",
        )
        db.add(p)
        return [p]

    from sqlalchemy.exc import IntegrityError
    with pytest.raises(IntegrityError):
        billing._generate_and_commit_payments(db, "REG-9999-", _build, max_attempts=3)
