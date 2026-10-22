"""Un stock produit ne doit jamais pouvoir descendre sous 0 — plusieurs
chemins manquaient ce controle : create_sale l'avait deja (voir
test_sale_warehouse_authorization.py), mais update_sale (modification d'une
vente existante), adjust_stock (ajustement manuel admin), et le retour
fournisseur (process_purchase_return) laissaient passer n'importe quelle
quantite OUT sans jamais verifier le stock disponible."""
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
from api.schemas.sale import SaleCreate, SaleUpdate, SaleItemInput
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
def depot(db, tenant):
    w = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(w)
    db.flush()
    return w


@pytest.fixture()
def product(db, tenant, category):
    p = Product(name="Produit", category_id=category.id, sale_price=100, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    return p


def _stock(db, tenant, product, warehouse_id, qty):
    db.add(StockMovement(product_id=product.id, type=StockType.in_, quantity=qty,
                          tenant_id=tenant.id, warehouse_id=warehouse_id))
    db.commit()


def test_update_sale_cannot_oversell_past_available_stock(db, tenant, product, depot):
    """Bug reel : create_sale verifiait le stock disponible, mais modifier
    une vente existante (augmenter la quantite d'un article) ne le faisait
    pas — un caissier pouvait faire passer le stock sous 0 simplement en
    editant une vente deja enregistree."""
    _stock(db, tenant, product, depot.id, qty=5)
    admin = SimpleNamespace(warehouse_id=[])

    sale = sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=500, payment_method="CASH", warehouse_id=depot.id,
            items=[SaleItemInput(product_id=product.id, quantity=5,
                                  unit_price=100, subtotal=500)],
        ),
        user_id="u1", tenant_id=tenant.id, current_user=admin,
    )
    db.commit()

    # Stock disponible = 0 apres cette vente de 5. Tenter de la modifier a
    # une quantite de 6 doit echouer, pas creer un stock a -1.
    with pytest.raises(HTTPException) as exc:
        sale_service.update_sale(
            db, sale.id,
            SaleUpdate(
                payment_method="CASH", additional_payment=0,
                items=[SaleItemInput(product_id=product.id, quantity=6,
                                      unit_price=100, subtotal=600)],
            ),
            user_id="u1", tenant_id=tenant.id,
        )
    assert exc.value.status_code == 400
    db.rollback()
    assert float(product.stock) == 0


def test_update_sale_can_still_reduce_quantity(db, tenant, product, depot):
    """Reduire la quantite (rendre du stock) doit toujours fonctionner —
    seule une augmentation au-dela du disponible doit etre bloquee."""
    _stock(db, tenant, product, depot.id, qty=5)
    admin = SimpleNamespace(warehouse_id=[])

    sale = sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=500, payment_method="CASH", warehouse_id=depot.id,
            items=[SaleItemInput(product_id=product.id, quantity=5,
                                  unit_price=100, subtotal=500)],
        ),
        user_id="u1", tenant_id=tenant.id, current_user=admin,
    )
    db.commit()

    sale_service.update_sale(
        db, sale.id,
        SaleUpdate(
            payment_method="CASH", additional_payment=0,
            items=[SaleItemInput(product_id=product.id, quantity=2,
                                  unit_price=100, subtotal=200)],
        ),
        user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    assert float(product.stock) == 3
