"""Système de fidélisation : crédit en % du montant de la vente sur un solde
client utilisable (pas des points), activable via AppConfig.loyalty_enabled/
loyalty_percent. Rédemption = champ séparé (loyalty_redeemed) qui réduit ce
qui reste à payer par le moyen de paiement choisi, sans le remplacer."""
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.Customer import Customer
from api.models.AppConfig import AppConfig
from api.models.Sale import Sale
from api.models.Payment import Payment
from api.models.StockMovement import StockMovement, StockType
from api.models.Warehouse import Warehouse
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
    p = Product(
        name="Produit", category_id=cat.id, sale_price=1000, tenant_id=tenant.id,
    )
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=100, tenant_id=tenant.id))
    db.flush()
    return p


@pytest.fixture()
def customer(db, tenant):
    c = Customer(name="Client", phone="50900000000", address="Rue", tenant_id=tenant.id)
    db.add(c)
    db.flush()
    return c


def _sale_data(product, customer_id=None, paid_amount=1000, loyalty_redeemed=0):
    return SaleCreate(
        customer_id=customer_id,
        paid_amount=paid_amount,
        payment_method="CASH",
        loyalty_redeemed=loyalty_redeemed,
        items=[SaleItemInput(
            product_id=product.id, quantity=1, unit_price=1000, subtotal=1000,
        )],
    )


def _enable_loyalty(db, tenant, percent=2):
    cfg = AppConfig(tenant_id=tenant.id, loyalty_enabled=True, loyalty_percent=percent)
    db.add(cfg)
    db.flush()
    return cfg


def test_loyalty_earned_credited_on_sale(db, tenant, product, customer):
    _enable_loyalty(db, tenant, percent=2)

    sale = sale_service.create_sale(
        db, _sale_data(product, customer_id=customer.id), user_id="u1", tenant_id=tenant.id,
    )

    db.refresh(customer)
    assert sale.loyalty_earned == Decimal("20.00")
    assert customer.loyalty_balance == Decimal("20.00")


def test_loyalty_disabled_earns_nothing(db, tenant, product, customer):
    # Pas de AppConfig avec loyalty_enabled — reste à sa valeur par défaut (False).
    sale = sale_service.create_sale(
        db, _sale_data(product, customer_id=customer.id), user_id="u1", tenant_id=tenant.id,
    )
    db.refresh(customer)
    assert sale.loyalty_earned == 0
    assert customer.loyalty_balance == 0


def test_loyalty_enabled_only_at_depot_level_still_earns(db, tenant, product, customer):
    """Régression : AppConfig (donc loyalty_enabled/loyalty_percent) est
    configurable par dépôt (voir api/routes/config.py) — create_sale doit lire
    la config DU DÉPÔT de la vente, pas seulement la config globale du tenant
    (warehouse_id=NULL). Avant le fix, create_sale appelait
    config_service.get_or_create(db, tenant_id=tenant_id) sans warehouse_id :
    une fidélisation activée uniquement au niveau d'un dépôt (cas courant —
    réglages ouverts depuis ce poste) n'était donc jamais prise en compte."""
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt A", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    db.add(StockMovement(
        product_id=product.id, type=StockType.in_, quantity=100,
        tenant_id=tenant.id, warehouse_id=wh.id,
    ))
    # Config globale (warehouse_id=NULL) : fidélisation désactivée.
    db.add(AppConfig(tenant_id=tenant.id, loyalty_enabled=False))
    # Config du dépôt : fidélisation activée à 2%.
    db.add(AppConfig(tenant_id=tenant.id, warehouse_id=wh.id, loyalty_enabled=True, loyalty_percent=2))
    db.flush()

    data = _sale_data(product, customer_id=customer.id)
    data.warehouse_id = wh.id
    sale = sale_service.create_sale(db, data, user_id="u1", tenant_id=tenant.id)

    db.refresh(customer)
    assert sale.loyalty_earned == Decimal("20.00")
    assert customer.loyalty_balance == Decimal("20.00")


def test_no_customer_no_earning(db, tenant, product):
    """Sans client identifié, pas de fidélisation possible."""
    _enable_loyalty(db, tenant, percent=2)
    sale = sale_service.create_sale(
        db, _sale_data(product, customer_id=None), user_id="u1", tenant_id=tenant.id,
    )
    assert sale.loyalty_earned == 0


def test_redemption_reduces_debt_and_creates_loyalty_payment(db, tenant, product, customer):
    customer.loyalty_balance = Decimal("50.00")
    db.commit()

    sale = sale_service.create_sale(
        db,
        _sale_data(product, customer_id=customer.id, paid_amount=950, loyalty_redeemed=50),
        user_id="u1", tenant_id=tenant.id,
    )

    db.refresh(customer)
    assert sale.loyalty_redeemed == Decimal("50.00")
    assert sale.status.value == "PAID"  # 950 cash + 50 fidélité = 1000
    assert customer.loyalty_balance == Decimal("0.00")

    loyalty_payment = db.query(Payment).filter_by(reference_id=sale.id, method="LOYALTY").first()
    assert loyalty_payment is not None
    assert loyalty_payment.amount == Decimal("50.00")


def test_redemption_clamped_to_customer_balance(db, tenant, product, customer):
    """Le client ne peut jamais utiliser plus que son solde réel, même si le
    payload en demande plus (clamp silencieux, pas d'erreur 400 — le solde a
    pu changer entre l'affichage et la soumission)."""
    customer.loyalty_balance = Decimal("30.00")
    db.commit()

    sale = sale_service.create_sale(
        db,
        _sale_data(product, customer_id=customer.id, paid_amount=1000, loyalty_redeemed=200),
        user_id="u1", tenant_id=tenant.id,
    )

    db.refresh(customer)
    assert sale.loyalty_redeemed == Decimal("30.00")
    assert customer.loyalty_balance == Decimal("0.00")


def test_redemption_clamped_to_sale_total(db, tenant, product, customer):
    """Impossible de redeem plus que le montant de la vente elle-même."""
    customer.loyalty_balance = Decimal("5000.00")
    db.commit()

    sale = sale_service.create_sale(
        db,
        _sale_data(product, customer_id=customer.id, paid_amount=0, loyalty_redeemed=5000),
        user_id="u1", tenant_id=tenant.id,
    )

    assert sale.loyalty_redeemed == Decimal("1000.00")  # capé au total de la vente


def test_no_earning_on_redeemed_portion(db, tenant, product, customer):
    """Anti-boucle : la portion payée EN fidélité n'est jamais elle-même
    génératrice de nouvelle fidélité."""
    _enable_loyalty(db, tenant, percent=10)
    customer.loyalty_balance = Decimal("1000.00")
    db.commit()

    sale = sale_service.create_sale(
        db,
        _sale_data(product, customer_id=customer.id, paid_amount=0, loyalty_redeemed=1000),
        user_id="u1", tenant_id=tenant.id,
    )

    # earn_base = 1000 (total) - 1000 (redeemed) = 0 → aucun gain
    assert sale.loyalty_earned == 0
    db.refresh(customer)
    # solde : 1000 (départ) - 1000 (utilisé) + 0 (gagné) = 0
    assert customer.loyalty_balance == Decimal("0.00")


def test_cancel_sale_reverses_earned_and_refunds_redeemed(db, tenant, product, customer):
    _enable_loyalty(db, tenant, percent=2)
    customer.loyalty_balance = Decimal("50.00")
    db.commit()

    sale = sale_service.create_sale(
        db,
        _sale_data(product, customer_id=customer.id, paid_amount=950, loyalty_redeemed=50),
        user_id="u1", tenant_id=tenant.id,
    )
    db.refresh(customer)
    # 50 (départ) - 50 (utilisé) + earned(950*2%=19.00) = 19.00
    assert customer.loyalty_balance == Decimal("19.00")

    sale_service.cancel_sale(db, sale.id, user_id="u1", tenant_id=tenant.id)

    db.refresh(customer)
    db.refresh(sale)
    assert sale.status.value == "CANCELLED"
    # reprend les 19.00 gagnés, rembourse les 50.00 utilisés → retour à 50.00
    assert customer.loyalty_balance == Decimal("50.00")


def test_cancel_sale_balance_never_negative(db, tenant, product, customer):
    """Garde-fou : même dans un cas limite improbable, le solde ne doit
    jamais devenir négatif après une annulation."""
    sale = Sale(
        tenant_id=tenant.id, customer_id=customer.id, reference="VNT-TEST",
        total_amount=100, final_amount=100, paid_amount=100,
        loyalty_earned=Decimal("999.00"), loyalty_redeemed=0, status="PAID",
    )
    db.add(sale)
    db.commit()

    sale_service.cancel_sale(db, sale.id, user_id="u1", tenant_id=tenant.id)

    db.refresh(customer)
    assert customer.loyalty_balance == Decimal("0.00")
