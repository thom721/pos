"""Bug reel, constate sur des recus imprimes : un rabais SAISI LIBREMENT
(pas de discount_id, "Remise caisse" sans nom de rabais) n'etait jamais
plafonne contre le sous-total, contrairement a un rabais catalogue
(compute_amount clampe deja via min(amount, base)). Une "Remise caisse"
superieure au sous-total produisait un final_amount NEGATIF, affiche
comme de la "monnaie a rendre" sur un encaissement jamais recu (Montant
recu = 0,00) - faille exploitable pour faire sortir de la marchandise
gratuitement, voire pire. Corrige en appliquant le meme plafond
[0, base] que compute_amount, directement dans resolve_discount."""
from decimal import Decimal

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
from api.models.Discount import DiscountScope
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service
from api.services.discount_service import resolve_discount


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


def test_free_text_discount_never_exceeds_base(db):
    """Reproduit exactement le 2e recu : sous-total 279.98, remise 300."""
    amount, disc_id = resolve_discount(
        db, None, 300, {DiscountScope.receipt, DiscountScope.both},
        Decimal("279.98"),
    )
    assert disc_id is None
    assert amount == Decimal("279.98"), "la remise ne doit jamais depasser le sous-total"


def test_free_text_discount_never_negative(db):
    amount, _ = resolve_discount(
        db, None, -50, {DiscountScope.receipt, DiscountScope.both}, Decimal("100"),
    )
    assert amount == Decimal("0")


def test_free_text_discount_zero_base_returns_zero(db):
    amount, _ = resolve_discount(
        db, None, 50, {DiscountScope.receipt, DiscountScope.both}, Decimal("0"),
    )
    assert amount == Decimal("0")


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


def test_create_sale_final_amount_never_negative_from_oversized_discount(
    db, tenant, category, depot,
):
    """Meme scenario que le 2e recu, via create_sale de bout en bout."""
    p = Product(name="Produit", category_id=category.id, sale_price=23.33, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=20,
                          tenant_id=tenant.id, warehouse_id=depot.id))
    db.commit()

    sale = sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=0, payment_method="CASH", warehouse_id=depot.id,
            discount=300,  # saisie libre, superieure au sous-total (279.98)
            items=[SaleItemInput(product_id=p.id, quantity=12,
                                  unit_price=23.33, subtotal=279.96)],
        ),
        user_id="u1", tenant_id=tenant.id, current_user=None,
    )
    db.commit()

    assert sale.final_amount >= 0, (
        "final_amount ne doit jamais etre negatif — une remise caisse trop "
        "grande ne doit pas generer de fausse monnaie a rendre"
    )
    assert float(sale.discount) <= float(sale.total_amount) + 0.01
