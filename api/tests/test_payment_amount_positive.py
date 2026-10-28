"""Bug reel : POST /api/payments/ (add_payment) acceptait n'importe quel
montant, y compris negatif ou nul, sans validation. Un montant negatif
reduisait silencieusement entity.paid_amount, pouvant repasser une vente
deja PAYEE en PARTIELLE/IMPAYEE via le point d'entree normal "nouveau
paiement" — sans aucun lien avec le mecanisme de remboursement legitime
(return_service.py, qui construit son Payment(amount negatif) directement,
sans passer par add_payment/PaymentCreate).

Regle affinee sur demande : SALE tolere un montant de 0 (jamais negatif) ;
PURCHASE et tout le reste (ex: encaissement d'une dette) rejette aussi 0,
puisqu'un paiement de 0 n'a aucun sens dans ces cas."""
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.Warehouse import Warehouse
from api.models.Supplier import Supplier
from api.models.Purchase import Purchase
from api.models.StockMovement import StockMovement, StockType
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service, payment_service


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def paid_sale(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Dépôt", is_active=True, is_default=True)
    cat = Category(name="Cat", tenant_id=t.id)
    db.add_all([wh, cat])
    db.flush()
    p = Product(name="Produit", category_id=cat.id, sale_price=100, tenant_id=t.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10,
                          tenant_id=t.id, warehouse_id=wh.id))
    db.commit()

    sale = sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=300, payment_method="CASH", warehouse_id=wh.id,
            items=[SaleItemInput(product_id=p.id, quantity=3,
                                  unit_price=100, subtotal=300)],
        ),
        user_id="u1", tenant_id=t.id, current_user=None,
    )
    db.commit()
    return sale


def test_negative_payment_amount_rejected(db, paid_sale):
    with pytest.raises(HTTPException) as exc:
        payment_service.add_payment(
            db,
            SimpleNamespace(reference_type="SALE", reference_id=paid_sale.id,
                             amount=-50, method="cash"),
            user_id="u1",
        )
    assert exc.value.status_code == 400
    db.refresh(paid_sale)
    assert paid_sale.status.value == "PAID", "le statut ne doit pas avoir change"


def test_zero_payment_amount_tolerated_for_sale(db, paid_sale):
    # Regle affinee : SALE tolere 0 (pas negatif) — aucune exception.
    payment_service.add_payment(
        db,
        SimpleNamespace(reference_type="SALE", reference_id=paid_sale.id,
                         amount=0, method="cash"),
        user_id="u1",
    )
    db.refresh(paid_sale)
    assert paid_sale.status.value == "PAID"


def test_zero_payment_amount_rejected_for_purchase(db, tenant_with_purchase):
    with pytest.raises(HTTPException) as exc:
        payment_service.add_payment(
            db,
            SimpleNamespace(reference_type="PURCHASE", reference_id=tenant_with_purchase.id,
                             amount=0, method="cash"),
            user_id="u1",
        )
    assert exc.value.status_code == 400


def test_negative_payment_amount_rejected_for_purchase(db, tenant_with_purchase):
    with pytest.raises(HTTPException) as exc:
        payment_service.add_payment(
            db,
            SimpleNamespace(reference_type="PURCHASE", reference_id=tenant_with_purchase.id,
                             amount=-10, method="cash"),
            user_id="u1",
        )
    assert exc.value.status_code == 400


@pytest.fixture()
def tenant_with_purchase(db):
    t = Tenant(business_name="T3", owner_email="t3@t.com", slug="t3")
    db.add(t)
    db.flush()
    supplier = Supplier(tenant_id=t.id, name="Fournisseur", phone="0000", address="-")
    db.add(supplier)
    db.flush()
    purchase = Purchase(tenant_id=t.id, supplier_id=supplier.id, user_id="u1",
                         reference="ACH-0001", total_amount=500, paid_amount=0)
    db.add(purchase)
    db.commit()
    return purchase


def test_positive_payment_amount_still_works(db, paid_sale):
    # Regression check : un vrai paiement positif doit continuer a fonctionner.
    t2 = Tenant(business_name="T2", owner_email="t2@t.com", slug="t2")
    db.add(t2)
    db.flush()
    wh2 = Warehouse(tenant_id=t2.id, name="Dépôt2", is_active=True, is_default=True)
    cat2 = Category(name="Cat2", tenant_id=t2.id)
    db.add_all([wh2, cat2])
    db.flush()
    p2 = Product(name="Produit2", category_id=cat2.id, sale_price=100, tenant_id=t2.id)
    db.add(p2)
    db.flush()
    db.add(StockMovement(product_id=p2.id, type=StockType.in_, quantity=10,
                          tenant_id=t2.id, warehouse_id=wh2.id))
    db.commit()
    sale2 = sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=0, payment_method="CASH", warehouse_id=wh2.id,
            items=[SaleItemInput(product_id=p2.id, quantity=1,
                                  unit_price=100, subtotal=100)],
        ),
        user_id="u1", tenant_id=t2.id, current_user=None,
    )
    db.commit()

    payment_service.add_payment(
        db,
        SimpleNamespace(reference_type="SALE", reference_id=sale2.id,
                         amount=100, method="cash"),
        user_id="u1",
    )
    db.commit()
    db.refresh(sale2)
    assert sale2.status.value == "PAID"
