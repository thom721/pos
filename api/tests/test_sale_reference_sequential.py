"""Numéro de reçu séquentiel ("VNT-00001" au lieu de l'ancien horodatage
"VNT-<timestamp>"), scopé par (tenant_id, warehouse_id) — pas par tenant
seul : un tenant multi-dépôts peut avoir une installation locale distincte
par dépôt, chacune génère alors ses propres numéros offline avant synchro ;
un compteur par (tenant, dépôt) évite tout conflit entre deux dépôts."""
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
from api.models.Sale import Sale
from api.models.StockMovement import StockMovement, StockType
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service
from api.services.sale_service import _next_sale_reference


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
def two_depots(db, tenant):
    a = Warehouse(tenant_id=tenant.id, name="Dépôt A", is_active=True, is_default=True)
    b = Warehouse(tenant_id=tenant.id, name="Dépôt B", is_active=True, is_default=False)
    db.add_all([a, b])
    db.flush()
    return a, b


@pytest.fixture()
def product(db, tenant, category):
    p = Product(name="Produit", category_id=category.id, sale_price=100, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    return p


def _sale_data(product, warehouse_id, quantity=1):
    return SaleCreate(
        paid_amount=100 * quantity,
        payment_method="CASH",
        warehouse_id=warehouse_id,
        items=[SaleItemInput(
            product_id=product.id, quantity=quantity, unit_price=100, subtotal=100 * quantity,
        )],
    )


def test_first_sale_at_a_depot_gets_00001(db, tenant, product, two_depots):
    depot_a, _depot_b = two_depots
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.commit()

    sale = sale_service.create_sale(
        db, _sale_data(product, depot_a.id), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()

    assert sale.reference == "VNT-00001"


def test_sequential_numbers_increment_within_the_same_depot(db, tenant, product, two_depots):
    depot_a, _depot_b = two_depots
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.commit()

    refs = []
    for _ in range(3):
        sale = sale_service.create_sale(
            db, _sale_data(product, depot_a.id), user_id="u1", tenant_id=tenant.id,
        )
        db.commit()
        refs.append(sale.reference)

    assert refs == ["VNT-00001", "VNT-00002", "VNT-00003"]


def test_each_depot_has_its_own_independent_sequence(db, tenant, product, two_depots):
    """Le compteur est scopé par (tenant, dépôt) : deux dépôts du même
    tenant démarrent chacun à 00001, sans se marcher dessus — c'est
    précisément ce qui évite un conflit si chaque dépôt tourne sur sa propre
    installation locale et synchronise indépendamment vers le cloud."""
    depot_a, depot_b = two_depots
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_b.id))
    db.commit()

    sale_a1 = sale_service.create_sale(db, _sale_data(product, depot_a.id), user_id="u1", tenant_id=tenant.id)
    db.commit()
    sale_b1 = sale_service.create_sale(db, _sale_data(product, depot_b.id), user_id="u1", tenant_id=tenant.id)
    db.commit()
    sale_a2 = sale_service.create_sale(db, _sale_data(product, depot_a.id), user_id="u1", tenant_id=tenant.id)
    db.commit()

    assert sale_a1.reference == "VNT-00001"
    assert sale_b1.reference == "VNT-00001"  # même numéro que sale_a1, mais dépôt différent : pas un conflit
    assert sale_a2.reference == "VNT-00002"


def test_legacy_timestamp_references_are_ignored_by_the_new_sequence(db, tenant, product, two_depots):
    """Les anciennes ventes ("VNT-1786827154", format horodatage) ne doivent
    jamais influencer le calcul du prochain numéro séquentiel — sinon la
    séquence exploserait à un numéro à 10 chiffres au lieu de repartir de 1.
    LIKE 'VNT-_____' (exactement 5 caractères) les exclut naturellement."""
    depot_a, _depot_b = two_depots
    db.add(Sale(
        tenant_id=tenant.id, warehouse_id=depot_a.id, user_id="u1",
        reference="VNT-1786827154", total_amount=10, final_amount=10, paid_amount=10,
    ))
    db.commit()
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=10, tenant_id=tenant.id, warehouse_id=depot_a.id))
    db.commit()

    sale = sale_service.create_sale(
        db, _sale_data(product, depot_a.id), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()

    assert sale.reference == "VNT-00001"


def test_next_sale_reference_survives_a_gap_in_the_sequence(db, tenant, two_depots):
    """Même correctif que _generate_and_commit_payments (billing.py) : MAX()
    plutôt que COUNT(), immunisé contre un trou dans la séquence."""
    depot_a, _depot_b = two_depots
    for n in (1, 2, 3, 5):  # 0004 manquant
        db.add(Sale(
            tenant_id=tenant.id, warehouse_id=depot_a.id, user_id="u1",
            reference=f"VNT-{n:05d}", total_amount=10, final_amount=10, paid_amount=10,
        ))
    db.commit()

    assert _next_sale_reference(db, tenant.id, depot_a.id) == "VNT-00006"


def test_no_warehouse_tenant_scoped_purely_by_tenant(db, tenant, product):
    """Non-régression : un tenant sans AUCUN Warehouse (mono-dépôt/local)
    continue de fonctionner — warehouse_id=None est son propre compartiment,
    cohérent avec le comportement déjà établi de Product.stock_at."""
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=5, tenant_id=tenant.id, warehouse_id=None))
    db.commit()

    sale = sale_service.create_sale(
        db, _sale_data(product, None), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()

    assert sale.reference == "VNT-00001"
