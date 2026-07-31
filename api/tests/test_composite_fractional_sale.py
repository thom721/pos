"""Vente d'une quantité fractionnaire d'un produit composé (ex: 1.5 "Caisse").

`Product.stock` arrondit à l'unité inférieure pour l'affichage — vérifier
la disponibilité avec ce champ bloquerait à tort une vente fractionnaire
alors que le composant a assez de stock. `create_sale` doit utiliser
`Product.available_quantity` (non arrondi) pour cette vérification.
"""
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
from fastapi import HTTPException


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
def caisse(db, tenant, category):
    """"Caisse" = 12 x "Boîte" — Boîte a 20 unités en stock (1.66 caisse)."""
    boite = Product(
        name="Boîte lait", category_id=category.id, sale_price=100, tenant_id=tenant.id,
    )
    db.add(boite)
    db.flush()
    db.add(StockMovement(product_id=boite.id, type=StockType.in_, quantity=20, tenant_id=tenant.id))
    db.flush()

    caisse = Product(
        name="Caisse lait", category_id=category.id, sale_price=1000, tenant_id=tenant.id,
        component_product_id=boite.id, component_quantity=Decimal("12"),
    )
    db.add(caisse)
    db.flush()
    return caisse


def _sale_data(product, quantity):
    return SaleCreate(
        paid_amount=0,
        payment_method="CASH",
        items=[SaleItemInput(
            product_id=product.id, quantity=quantity, unit_price=1000,
            subtotal=1000 * quantity,
        )],
    )


def test_fractional_composite_sale_allowed_when_component_stock_suffices(db, tenant, caisse):
    """1.5 caisse nécessite 18 boîtes ; 20 en stock → doit passer, même si
    caisse.stock (affichage) n'affiche que "1" (20 // 12)."""
    assert caisse.stock == 1

    sale = sale_service.create_sale(
        db, _sale_data(caisse, 1.5), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()

    boite = caisse.component
    db.refresh(boite)
    assert boite.stock == 2  # 20 - (1.5 * 12) = 2 boîtes restantes
    assert sale is not None


def test_fractional_composite_sale_rejected_when_component_stock_insufficient(db, tenant, caisse):
    """2 caisses nécessitent 24 boîtes ; seulement 20 en stock → rejeté."""
    with pytest.raises(HTTPException) as exc:
        sale_service.create_sale(
            db, _sale_data(caisse, 2), user_id="u1", tenant_id=tenant.id,
        )
    assert exc.value.status_code == 400
