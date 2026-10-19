"""Restriction de crédit (AppConfig.allow_cashier_credit) : le frontend
bloquait déjà une vente sous-payée sans cette autorisation (pos_screen.dart),
mais rien ne l'appliquait côté serveur — un appel API direct pouvait la
contourner. create_sale rejette maintenant ce cas (400), sauf si
allow_cashier_credit est activé ou si l'utilisateur a la permission dédiée
sales.credit (même dérogation que le frontend) — volontairement distincte de
sales.discount et non accordée par défaut au rôle cashier, pour permettre un
octroi individuel, caissier par caissier."""
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
from api.models.Role import Role
from api.models.StockMovement import StockMovement, StockType
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service
from api.core.permissions import load_roles_from_db
from fastapi import HTTPException


class _FakeUser:
    def __init__(self, permissions=None, roles=None, tenant_id=None):
        self.permissions = permissions or []
        self.roles = roles or []
        self.tenant_id = tenant_id


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


def test_underpaid_sale_allowed_with_sales_credit_permission(db, tenant, product):
    """sales.credit outrepasse la restriction, même config par défaut (False)."""
    sale = sale_service.create_sale(
        db, _sale_data(product, 300), user_id="u1", tenant_id=tenant.id,
        current_user=_FakeUser(permissions=["sales.credit"]),
    )
    db.commit()
    assert sale is not None


def test_underpaid_sale_still_rejected_with_only_sales_discount_permission(db, tenant, product):
    """sales.discount seul ne suffit plus — c'est précisément le point : les
    deux capacités sont désormais dissociées."""
    with pytest.raises(HTTPException) as exc:
        sale_service.create_sale(
            db, _sale_data(product, 300), user_id="u1", tenant_id=tenant.id,
            current_user=_FakeUser(permissions=["sales.discount"]),
        )
    assert exc.value.status_code == 400


def test_fully_paid_sale_never_blocked_regardless_of_credit_config(db, tenant, product):
    """Paiement complet → jamais concerné par la restriction de crédit."""
    sale = sale_service.create_sale(
        db, _sale_data(product, 1000), user_id="u1", tenant_id=tenant.id,
        current_user=_FakeUser(),
    )
    db.commit()
    assert sale is not None


def test_underpaid_sale_allowed_with_custom_tenant_role_granting_credit(db, tenant, product):
    """Bug corrigé : has_permission() était appelée sans tenant_id dans
    sale_service — un rôle personnalisé (ex: "Caissier + Crédit", créé via
    l'écran Utilisateurs, vivant dans TENANT_ROLE_OVERRIDES, pas
    ROLE_PERMISSIONS) était donc toujours invisible ici, même correctement
    attribué à l'utilisateur. Vu en prod : la permission marchait bien pour
    /users/me (resolve_effective_permissions passe déjà tenant_id) mais la
    vente échouait quand même avec le même message d'erreur, renvoyé cette
    fois par le serveur plutôt que bloqué par le frontend."""
    role = Role(
        tenant_id=tenant.id, name="credit_caissier", label="Caissier + Crédit",
        is_builtin=False, permissions=["sales.credit"],
    )
    db.add(role)
    db.commit()
    load_roles_from_db(db.query(Role).all())

    sale = sale_service.create_sale(
        db, _sale_data(product, 300), user_id="u1", tenant_id=tenant.id,
        current_user=_FakeUser(
            roles=["cashier", "credit_caissier"],
            permissions=["cashier", "credit_caissier"],
            tenant_id=tenant.id,
        ),
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
