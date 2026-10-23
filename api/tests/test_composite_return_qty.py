"""Bug reel : _inject_returned_qty derivait returned_qty des StockMovement
(source_type="sale_return"), mais record_stock_movement redirige TOUJOURS un
mouvement sur un produit compose ("Caisse") vers son COMPOSANT (component_
product_id, en unites composant) — le retour n'apparaissait donc jamais sous
le product_id du produit compose lui-meme, et returned_qty restait a 0.
Consequence : _QuickReturnDialog (frontend) calcule la quantite encore
retournable comme quantity - returnedQty, donc une "Caisse" deja entierement
retournee pouvait etre retournee une seconde fois, remboursant deux fois et
regonflant le stock du composant au-dela de la realite physique.

Corrige en lisant returned_qty depuis ReturnRecord.items_json (qui porte
maintenant product_id), independant de la redirection composite->composant
des mouvements de stock."""
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
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service, return_service


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
def composite_product(db, tenant, category, depot):
    """Caisse de 12 Boîtes — 5 caisses en stock (60 boîtes)."""
    boite = Product(name="Boîte", category_id=category.id, sale_price=10, tenant_id=tenant.id)
    db.add(boite)
    db.flush()
    db.add(StockMovement(product_id=boite.id, type=StockType.in_, quantity=60,
                          tenant_id=tenant.id, warehouse_id=depot.id))
    db.commit()

    caisse = Product(
        name="Caisse", category_id=category.id, sale_price=100, tenant_id=tenant.id,
        component_product_id=boite.id, component_quantity=Decimal("12"),
    )
    db.add(caisse)
    db.commit()
    return caisse


def test_returned_qty_recorded_for_composite_product(db, tenant, composite_product, depot):
    caisse = composite_product

    sale = sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=100, payment_method="CASH", warehouse_id=depot.id,
            items=[SaleItemInput(product_id=caisse.id, quantity=1,
                                  unit_price=100, subtotal=100)],
        ),
        user_id="u1", tenant_id=tenant.id, current_user=None,
    )
    db.commit()

    return_service.process_sale_return(
        db, sale_id=sale.id, items=[{"product_id": caisse.id, "quantity": 1}],
        refund_amount=100, user_id="u1", tenant_id=tenant.id,
    )
    db.commit()

    reloaded = sale_service.get_sale(db, sale.id, tenant_id=tenant.id)
    assert reloaded.items[0].returned_qty == 1, (
        "la caisse retournee doit etre comptabilisee sous SON PROPRE product_id, "
        "pas seulement sous celui du composant"
    )


def test_fully_returned_composite_cannot_be_returned_twice(db, tenant, composite_product, depot):
    """Reproduit le bug reel : sans le fix, returned_qty restait a 0 apres un
    premier retour complet, laissant croire que toute la quantite etait
    encore retournable."""
    caisse = composite_product

    sale = sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=100, payment_method="CASH", warehouse_id=depot.id,
            items=[SaleItemInput(product_id=caisse.id, quantity=1,
                                  unit_price=100, subtotal=100)],
        ),
        user_id="u1", tenant_id=tenant.id, current_user=None,
    )
    db.commit()

    return_service.process_sale_return(
        db, sale_id=sale.id, items=[{"product_id": caisse.id, "quantity": 1}],
        refund_amount=100, user_id="u1", tenant_id=tenant.id,
    )
    db.commit()

    reloaded = sale_service.get_sale(db, sale.id, tenant_id=tenant.id)
    item = reloaded.items[0]
    remaining_returnable = float(item.quantity) - item.returned_qty
    assert remaining_returnable == 0, (
        "plus rien ne doit etre retournable apres un retour complet de la caisse"
    )
