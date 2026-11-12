"""GET /api/sessions/{id}/summary doit ventiler le recouvrement de dettes
par methode de paiement (cash vs banque), pas tout regrouper sous "cash" —
sinon un gros client qui rembourse sa dette par virement bancaire apparaît
dans le rapport comme s'il avait paye en especes, alors que ce montant ne
sera jamais dans le tiroir a la fermeture (voir pos_screen.dart,
_CloseSessionDialog)."""
from datetime import timedelta
from types import SimpleNamespace

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
from api.database import Base
from api.models.CashierSession import CashierSession
from api.models.Payment import Payment
from api.models.PosRegister import PosRegister
from api.models.Sale import Sale, SaleStatus
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.routes.cashier_sessions import session_summary


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


def _user(stub_id, tenant_id):
    return SimpleNamespace(id=stub_id, tenant_id=tenant_id, roles=["cashier"])


def test_debt_collected_split_between_cash_and_bank(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(tenant_id=t.id, warehouse_id=wh.id, name="Caisse 1",
                      device_id="dev-1", is_active=True, is_device_approved=True)
    cashier = User(tenant_id=t.id, fname="C", lname="C", username="cashier1",
                   email="c@t.com", password="x", roles=["cashier"])
    db.add_all([reg, cashier])
    db.flush()

    opened_at = now_local()
    session = CashierSession(tenant_id=t.id, register_id=reg.id, cashier_id=cashier.id,
                             warehouse_id=wh.id, opened_at=opened_at, opening_balance=0,
                             status="open")
    db.add(session)
    db.flush()

    # Vente a credit creee AVANT l'ouverture de la session (dette preexistante).
    old_sale = Sale(
        tenant_id=t.id, user_id=cashier.id, warehouse_id=wh.id,
        reference="V-OLD-1", total_amount=1000, final_amount=1000,
        paid_amount=0, status=SaleStatus.credit,
        created_at=opened_at - timedelta(days=5),
    )
    db.add(old_sale)
    db.flush()

    # Deux recouvrements pendant la session : 400 en especes, 600 par virement.
    db.add_all([
        Payment(tenant_id=t.id, reference_type="SALE", reference_id=old_sale.id,
                amount=400, method="cash", user_id=cashier.id),
        Payment(tenant_id=t.id, reference_type="SALE", reference_id=old_sale.id,
                amount=600, method="bank", user_id=cashier.id),
    ])
    db.commit()

    res = session_summary(session.id, db=db, current_user=_user(cashier.id, t.id))

    assert res["debt_collected"] == 1000
    assert res["debt_collected_cash"] == 400
    assert res["debt_collected_bank"] == 600
    # Le virement ne doit jamais etre compte dans le solde theorique du tiroir.
    assert res["total_cash_sales"] == 400
    assert res["total_bank_sales"] == 600
    assert res["expected_closing_balance"] == 400
