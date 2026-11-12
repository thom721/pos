"""GET /api/sessions/debt-collected-today doit aussi ventiler par methode
(debt_collected_today_bank), au meme titre que le resume de fermeture de
session — sinon un recouvrement de dette par virement se noie dans le
total affiche sur la carte dashboard/rapport "Recouvrement de dettes",
sans distinction possible du cash."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
from api.database import Base
from api.models.Payment import Payment
from api.models.Sale import Sale, SaleStatus
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.routes.cashier_sessions import debt_collected_today


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


def test_debt_collected_today_split_cash_bank(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Dépôt", is_active=True, is_default=True)
    admin = User(tenant_id=t.id, fname="A", lname="Dmin", username="admin1",
                 email="a@t.com", password="x", roles=["admin"], permissions=["all"])
    db.add_all([wh, admin])
    db.flush()

    old_sale = Sale(
        tenant_id=t.id, user_id=admin.id, warehouse_id=wh.id,
        reference="V-OLD-1", total_amount=1000, final_amount=1000,
        paid_amount=0, status=SaleStatus.credit,
        created_at=now_local() - timedelta(days=5),
    )
    db.add(old_sale)
    db.flush()
    db.add_all([
        Payment(tenant_id=t.id, reference_type="SALE", reference_id=old_sale.id,
                amount=400, method="cash", user_id=admin.id),
        Payment(tenant_id=t.id, reference_type="SALE", reference_id=old_sale.id,
                amount=600, method="bank", user_id=admin.id),
    ])
    db.commit()

    res = debt_collected_today(db=db, current_user=admin)

    assert res["debt_collected_today"] == 1000
    assert res["debt_collected_today_bank"] == 600
