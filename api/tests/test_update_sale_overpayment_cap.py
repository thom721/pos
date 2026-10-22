"""Bug reel : modifier une vente (update_sale) et saisir un additional_payment
superieur a ce qui restait du faisait passer sale.paid_amount AU-DELA de
sale.final_amount, sans jamais enregistrer l'exces comme change_due (contrairement
a create_sale, qui plafonne deja via collected = min(paid, remaining)). Une vente
avec paid_amount > final_amount a un solde (balance) NEGATIF, qui, agrege avec
d'autres ventes dans le dashboard ("Solde a recouvrer"/"Vente credit") ou le
rapport des ventes ("Reste a encaisser"), masquait a tort du credit reellement
du par d'AUTRES clients — la monnaie d'une vente modifiee "annulait" le credit
d'une autre dans la somme globale."""
from types import SimpleNamespace

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.Warehouse import Warehouse
from api.models.StockMovement import StockMovement, StockType
from api.schemas.sale import SaleCreate, SaleUpdate, SaleItemInput
from api.services import sale_service


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
def category(db, tenant):
    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    return cat


@pytest.fixture()
def depot(db, tenant):
    w = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(w)
    db.flush()
    return w


@pytest.fixture()
def product(db, tenant, category):
    p = Product(name="Produit", category_id=category.id, sale_price=100, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    return p


def test_additional_payment_above_balance_becomes_change_not_overpaid_credit(
    db, tenant, product, depot,
):
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10,
                          tenant_id=tenant.id, warehouse_id=depot.id))
    db.commit()
    admin = SimpleNamespace(warehouse_id=[])

    # Vente a credit : total 300, rien de paye.
    sale = sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=0, payment_method="CASH", warehouse_id=depot.id,
            items=[SaleItemInput(product_id=product.id, quantity=3,
                                  unit_price=100, subtotal=300)],
        ),
        user_id="u1", tenant_id=tenant.id, current_user=None,
    )
    db.commit()
    assert float(sale.balance) == 300

    # Le client donne 500 pour regler les 300 dus — 200 de monnaie a rendre,
    # pas un credit de -200 sur son compte.
    sale_service.update_sale(
        db, sale.id,
        SaleUpdate(payment_method="CASH", additional_payment=500,
                   items=[SaleItemInput(product_id=product.id, quantity=3,
                                         unit_price=100, subtotal=300)]),
        user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    db.refresh(sale)

    assert float(sale.paid_amount) == 300, (
        "paid_amount ne doit jamais depasser final_amount — l'exces est de la "
        "monnaie (change_due), pas un paiement"
    )
    assert float(sale.change_due) == 200
    assert float(sale.balance) == 0, "le solde ne doit jamais devenir negatif"
