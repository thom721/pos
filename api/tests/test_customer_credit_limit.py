"""Customer.credit_limit n'était vérifié nulle part — un client avec la
limite par défaut (0, "aucun crédit autorisé") pouvait accumuler de la dette
sans aucune restriction en payant partiellement/pas du tout une vente.
_enforce_credit_limit (sale_service.py) bloque désormais toute vente qui
ferait dépasser ce plafond, en tenant compte des dettes déjà existantes."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.Customer import Customer
from api.models.StockMovement import StockMovement, StockType
from api.models.Debt import Debt
from api.schemas.sale import SaleCreate, SaleItemInput, SaleUpdate
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
    p = Product(name="Produit", category_id=cat.id, sale_price=100,
                purchase_price=50, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=100, tenant_id=tenant.id))
    db.commit()
    return p


def _customer(db, tenant, credit_limit):
    c = Customer(name="Client", tenant_id=tenant.id, phone="12345678",
                 address="Adresse", credit_limit=credit_limit)
    db.add(c)
    db.commit()
    return c


def _credit_sale_data(product, customer, amount, paid=0):
    return SaleCreate(
        customer_id=customer.id,
        paid_amount=paid,
        payment_method="CASH",
        items=[SaleItemInput(
            product_id=product.id, quantity=1, unit_price=amount, subtotal=amount,
        )],
    )


def test_credit_sale_rejected_for_zero_limit_customer(db, tenant, product):
    """Limite par défaut (0) = aucun crédit autorisé — toute vente non
    intégralement payée doit être rejetée."""
    customer = _customer(db, tenant, credit_limit=0)

    with pytest.raises(HTTPException) as exc:
        sale_service.create_sale(
            db, _credit_sale_data(product, customer, 100, paid=0),
            user_id="u1", tenant_id=tenant.id,
        )
    assert exc.value.status_code == 400
    assert "Limite de crédit" in exc.value.detail


def test_credit_sale_allowed_within_limit(db, tenant, product):
    customer = _customer(db, tenant, credit_limit=200)

    sale = sale_service.create_sale(
        db, _credit_sale_data(product, customer, 100, paid=0),
        user_id="u1", tenant_id=tenant.id,
    )
    assert sale is not None
    debt = db.query(Debt).filter_by(partner_id=customer.id).first()
    assert float(debt.balance) == 100


def test_credit_sale_rejected_when_exceeding_limit_with_existing_debt(db, tenant, product):
    """Une dette déjà existante (ex: vente précédente) consomme une partie de
    la limite ; une nouvelle vente qui dépasserait le reste doit être
    rejetée, même si elle serait sous la limite prise isolément."""
    customer = _customer(db, tenant, credit_limit=150)
    db.add(Debt(
        tenant_id=tenant.id, reference_type="SALE", reference_id="other-sale",
        partner_type="CUSTOMER", partner_id=customer.id,
        total_amount=100, paid_amount=0, balance=100, status="UNPAID",
    ))
    db.commit()

    with pytest.raises(HTTPException) as exc:
        sale_service.create_sale(
            db, _credit_sale_data(product, customer, 100, paid=0),
            user_id="u1", tenant_id=tenant.id,
        )
    assert exc.value.status_code == 400


def test_partial_payment_within_limit_allowed(db, tenant, product):
    """Un paiement partiel qui laisse un solde sous la limite doit passer."""
    customer = _customer(db, tenant, credit_limit=50)

    sale = sale_service.create_sale(
        db, _credit_sale_data(product, customer, 100, paid=60),
        user_id="u1", tenant_id=tenant.id,
    )
    assert sale is not None
    debt = db.query(Debt).filter_by(partner_id=customer.id).first()
    assert float(debt.balance) == 40


def test_fully_paid_sale_never_blocked_regardless_of_limit(db, tenant, product):
    """Une vente intégralement payée (balance=0) ne crée pas de dette — la
    limite de crédit n'a pas lieu d'être vérifiée."""
    customer = _customer(db, tenant, credit_limit=0)

    sale = sale_service.create_sale(
        db, _credit_sale_data(product, customer, 100, paid=100),
        user_id="u1", tenant_id=tenant.id,
    )
    assert sale is not None
    assert db.query(Debt).filter_by(partner_id=customer.id).count() == 0


def test_update_sale_does_not_double_count_its_own_existing_debt(db, tenant, product):
    """Modifier une vente déjà à crédit ne doit pas compter sa propre dette
    deux fois (une fois comme "dette existante", une fois comme "nouvelle
    dette") — sinon même une vente inchangée finirait par sembler dépasser
    la limite."""
    customer = _customer(db, tenant, credit_limit=100)

    sale = sale_service.create_sale(
        db, _credit_sale_data(product, customer, 100, paid=0),
        user_id="u1", tenant_id=tenant.id,
    )

    # Re-soumet la même vente (même montant, même client) — doit toujours
    # passer puisque le solde total dû ne change pas.
    update_data = SaleUpdate(
        customer_id=customer.id,
        additional_payment=0,
        payment_method="CASH",
        items=[SaleItemInput(
            product_id=product.id, quantity=1, unit_price=100, subtotal=100,
        )],
    )
    updated = sale_service.update_sale(db, sale.id, update_data, user_id="u1", tenant_id=tenant.id)
    assert updated is not None
