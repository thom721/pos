"""Restriction de crédit (AppConfig.allow_cashier_credit) : le frontend
bloquait déjà une vente sous-payée sans cette autorisation (pos_screen.dart),
mais rien ne l'appliquait côté serveur — un appel API direct pouvait la
contourner. create_sale rejette maintenant ce cas (400), sauf si
allow_cashier_credit est activé ou si l'utilisateur a la permission
sales.discount (même dérogation que le frontend)."""
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.AppConfig import AppConfig
from api.models.StockMovement import StockMovement, StockType
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service
from fastapi import HTTPException


class _FakeUser:
    def __init__(self, permissions=None, roles=None):
        self.permissions = permissions or []
        self.roles = roles or []


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
    p = Product(name="Produit", category_id=cat.id, sale_price=1000, tenant_id=tenant.id)
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
            product_id=product.id, quantity=1, unit_price=1000, subtotal=1000,
        )],
    )


def test_underpaid_sale_rejected_when_credit_not_allowed(db, tenant, product):
    """allow_cashier_credit=False (défaut) et pas de permission → 400."""
    with pytest.raises(HTTPException) as exc:
        sale_service.create_sale(
            db, _sale_data(product, 300), user_id="u1", tenant_id=tenant.id,
            current_user=_FakeUser(),
        )
    assert exc.value.status_code == 400
    assert "crédit" in exc.value.detail


def test_underpaid_sale_allowed_when_config_permits_credit(db, tenant, product):
    db.add(AppConfig(tenant_id=tenant.id, allow_cashier_credit=True))
    db.flush()

    sale = sale_service.create_sale(
        db, _sale_data(product, 300), user_id="u1", tenant_id=tenant.id,
        current_user=_FakeUser(),
    )
    db.commit()
    assert sale is not None
    assert sale.paid_amount == Decimal("300.00")


def test_underpaid_sale_allowed_with_sales_discount_permission(db, tenant, product):
    """sales.discount outrepasse la restriction, même config par défaut (False)."""
    sale = sale_service.create_sale(
        db, _sale_data(product, 300), user_id="u1", tenant_id=tenant.id,
        current_user=_FakeUser(permissions=["sales.discount"]),
    )
    db.commit()
    assert sale is not None


def test_fully_paid_sale_never_blocked_regardless_of_credit_config(db, tenant, product):
    """Paiement complet → jamais concerné par la restriction de crédit."""
    sale = sale_service.create_sale(
        db, _sale_data(product, 1000), user_id="u1", tenant_id=tenant.id,
        current_user=_FakeUser(),
    )
    db.commit()
    assert sale is not None


def test_no_current_user_skips_check_for_internal_callers(db, tenant, product):
    """Sans current_user (appel interne/test), la vérification est ignorée —
    ne casse pas les appelants existants qui ne la fournissent pas."""
    sale = sale_service.create_sale(
        db, _sale_data(product, 300), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    assert sale is not None
