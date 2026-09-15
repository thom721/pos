"""Un cashier restreint à un sous-ensemble de dépôts (User.warehouse_id non
vide) ne doit jamais pouvoir enregistrer une vente pour un AUTRE dépôt du
même tenant — même si le client envoie ce warehouse_id dans le payload.

Bug constaté en prod : un cashier assigné uniquement au dépôt "PROMESSE DE
DIEU" a eu une vente comptabilisée sur le dépôt "NES" du même tenant,
faussant la numérotation séquentielle des deux dépôts (aucun contrôle
serveur ne vérifiait l'appartenance du warehouse_id à la liste autorisée
de l'utilisateur — voir create_sale, sale_service.py)."""
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


def _sale_data(product, warehouse_id):
    return SaleCreate(
        paid_amount=100,
        payment_method="CASH",
        warehouse_id=warehouse_id,
        items=[SaleItemInput(
            product_id=product.id, quantity=1, unit_price=100, subtotal=100,
        )],
    )


def _stock(db, tenant, product, warehouse_id, qty=10):
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=qty,
                          tenant_id=tenant.id, warehouse_id=warehouse_id))
    db.commit()


def test_cashier_restricted_to_depot_a_cannot_sell_for_depot_b(db, tenant, product, two_depots):
    depot_a, depot_b = two_depots
    _stock(db, tenant, product, depot_a.id)
    _stock(db, tenant, product, depot_b.id)
    cashier = SimpleNamespace(warehouse_id=[depot_a.id])

    with pytest.raises(HTTPException) as exc:
        sale_service.create_sale(
            db, _sale_data(product, depot_b.id), user_id="u1", tenant_id=tenant.id,
            current_user=cashier,
        )
    assert exc.value.status_code == 403


def test_cashier_restricted_to_depot_a_can_sell_for_depot_a(db, tenant, product, two_depots):
    depot_a, _depot_b = two_depots
    _stock(db, tenant, product, depot_a.id)
    cashier = SimpleNamespace(warehouse_id=[depot_a.id])

    sale = sale_service.create_sale(
        db, _sale_data(product, depot_a.id), user_id="u1", tenant_id=tenant.id,
        current_user=cashier,
    )
    db.commit()
    assert sale.warehouse_id == depot_a.id


def test_no_warehouse_in_payload_defaults_to_cashiers_own_depot(db, tenant, product, two_depots):
    """Bug constate en prod : le client n'envoie parfois AUCUN warehouse_id
    (ex: etat app pas encore charge). resolve_warehouse_id(None) retombe sur
    le depot PAR DEFAUT DU TENANT (depot_a ici) — dangereux pour un cashier
    restreint a un AUTRE depot (depot_b, non-defaut) : sa vente atterrissait
    sur le mauvais business. Doit desormais retomber sur SON propre depot
    quand il n'en a qu'un seul assigne, pas celui du tenant."""
    depot_a, depot_b = two_depots
    assert depot_a.is_default and not depot_b.is_default
    _stock(db, tenant, product, depot_b.id)
    cashier = SimpleNamespace(warehouse_id=[depot_b.id])

    sale = sale_service.create_sale(
        db, _sale_data(product, None), user_id="u1", tenant_id=tenant.id,
        current_user=cashier,
    )
    db.commit()
    assert sale.warehouse_id == depot_b.id


def test_no_warehouse_and_no_way_to_infer_one_is_rejected(db, tenant, product, two_depots):
    """Un tenant multi-depots ne doit jamais deviner silencieusement lequel —
    ni pour un cashier non-restreint (liste vide) qui n'a pas de "depot
    unique" a inferer, ni sans current_user du tout. Doit rejeter (400)
    plutot que de retomber sur le depot par defaut du tenant."""
    depot_a, depot_b = two_depots
    _stock(db, tenant, product, depot_a.id)
    admin = SimpleNamespace(warehouse_id=[])

    with pytest.raises(HTTPException) as exc:
        sale_service.create_sale(
            db, _sale_data(product, None), user_id="u1", tenant_id=tenant.id,
            current_user=admin,
        )
    assert exc.value.status_code == 400


def test_unrestricted_user_can_sell_for_any_depot(db, tenant, product, two_depots):
    depot_a, depot_b = two_depots
    _stock(db, tenant, product, depot_b.id)
    admin = SimpleNamespace(warehouse_id=[])  # liste vide = accès à tous les dépôts

    sale = sale_service.create_sale(
        db, _sale_data(product, depot_b.id), user_id="u1", tenant_id=tenant.id,
        current_user=admin,
    )
    db.commit()
    assert sale.warehouse_id == depot_b.id
