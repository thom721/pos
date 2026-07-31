"""Monnaie rendue : create_sale plafonne toujours Sale.paid_amount au montant
dû (la caisse ne garde jamais plus que la vente) — l'excédent remis en
espèces doit être conservé dans Sale.change_due pour pouvoir l'afficher sur
le reçu, sinon il est silencieusement perdu."""
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.StockMovement import StockMovement, StockType
from api.schemas.sale import SaleCreate, SaleItemInput
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
def product(db, tenant):
    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    p = Product(name="Produit", category_id=cat.id, sale_price=750, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=100, tenant_id=tenant.id))
    db.flush()
    return p


def _sale_data(product, paid_amount):
    return SaleCreate(
        paid_amount=paid_amount,
        payment_method="CASH",
        items=[SaleItemInput(
            product_id=product.id, quantity=1, unit_price=750, subtotal=750,
        )],
    )


def test_change_due_recorded_on_overpayment(db, tenant, product):
    """Client tend 1000 HTG pour une vente à 750 HTG → change_due = 250."""
    sale = sale_service.create_sale(
        db, _sale_data(product, 1000), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    db.refresh(sale)

    assert sale.paid_amount == Decimal("750.00")  # jamais plus que le dû
    assert sale.change_due == Decimal("250.00")


def test_change_due_zero_on_exact_payment(db, tenant, product):
    sale = sale_service.create_sale(
        db, _sale_data(product, 750), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    db.refresh(sale)

    assert sale.paid_amount == Decimal("750.00")
    assert sale.change_due == Decimal("0.00")


def test_change_due_zero_on_partial_payment(db, tenant, product):
    """Paiement partiel (crédit) → pas de monnaie à rendre."""
    sale = sale_service.create_sale(
        db, _sale_data(product, 300), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    db.refresh(sale)

    assert sale.paid_amount == Decimal("300.00")
    assert sale.change_due == Decimal("0.00")
