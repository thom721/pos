"""Tests des produits composés (ex: "Caisse" = 12 x "Boîte") : la conversion
de stock doit toujours cibler le produit composant, jamais le composé."""
import pytest
from decimal import Decimal

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # enregistre tous les modèles auprès de Base.metadata
from api.database import Base
from api.models.Category import Category
from api.models.Product import Product
from api.models.StockMovement import StockMovement, StockType
from api.services.stock_service import record_stock_movement


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def category(db):
    cat = Category(name="Boissons")
    db.add(cat)
    db.flush()
    return cat


def _make_product(db, category, **kwargs):
    p = Product(
        category_id=category.id,
        purchase_price=Decimal("1.0"),
        sale_price=Decimal("2.0"),
        alert_stock=0,
        **kwargs,
    )
    db.add(p)
    db.flush()
    return p


def test_non_composite_movement_targets_itself(db, category):
    """Un produit normal reçoit son mouvement directement, quantité inchangée."""
    boite = _make_product(db, category, name="Boîte lait")

    mv = record_stock_movement(
        db, product_id=boite.id, quantity=-3, type=StockType.out,
        source_type="SALE",
    )
    db.commit()

    assert mv.product_id == boite.id
    assert mv.quantity == Decimal("-3")


def test_composite_sale_redirects_to_component(db, category):
    """Vendre 2 "Caisse" (12 Boîtes/caisse) doit décrémenter Boîte de 24."""
    boite = _make_product(db, category, name="Boîte lait")
    caisse = _make_product(
        db, category, name="Caisse lait",
        component_product_id=boite.id, component_quantity=Decimal("12"),
    )

    mv = record_stock_movement(
        db, product_id=caisse.id, quantity=-2, type=StockType.out,
        source_type="SALE", note="Vente POS",
    )
    db.commit()

    # Le mouvement cible bien Boîte, pas Caisse
    assert mv.product_id == boite.id
    assert mv.quantity == Decimal("-24")
    assert "Caisse lait" in (mv.note or "")

    # Aucun mouvement n'a jamais été créé pour Caisse elle-même
    caisse_movements = db.query(StockMovement).filter_by(product_id=caisse.id).all()
    assert caisse_movements == []


def test_composite_purchase_receipt_redirects_and_multiplies(db, category):
    """Recevoir 5 "Caisse" doit créditer Boîte de 60 (5 x 12), pas Caisse."""
    boite = _make_product(db, category, name="Boîte lait")
    caisse = _make_product(
        db, category, name="Caisse lait",
        component_product_id=boite.id, component_quantity=Decimal("12"),
    )

    mv = record_stock_movement(
        db, product_id=caisse.id, quantity=5, type=StockType.in_,
        source_type="purchase_receipt",
    )
    db.commit()

    assert mv.product_id == boite.id
    assert mv.quantity == Decimal("60")


def test_composite_stock_is_derived_from_component(db, category):
    """Product.stock d'un composé = stock du composant // component_quantity."""
    boite = _make_product(db, category, name="Boîte lait")
    caisse = _make_product(
        db, category, name="Caisse lait",
        component_product_id=boite.id, component_quantity=Decimal("12"),
    )

    db.add(StockMovement(product_id=boite.id, type=StockType.in_, quantity=100))
    db.commit()
    db.refresh(boite)
    db.refresh(caisse)

    assert boite.stock == 100
    # 100 boîtes // 12 par caisse = 8 caisses complètes (pas de demi-caisse)
    assert caisse.stock == 8


def test_composite_adjust_stock_via_endpoint_helper(db, category):
    """L'ajustement manuel de stock (page Produits) convertit aussi correctement."""
    boite = _make_product(db, category, name="Boîte lait")
    caisse = _make_product(
        db, category, name="Caisse lait",
        component_product_id=boite.id, component_quantity=Decimal("12"),
    )

    # Ajustement positif de 3 caisses (ex: entrée manuelle de stock)
    record_stock_movement(
        db, product_id=caisse.id, quantity=3, type=StockType.in_,
        source_type="adjustment",
    )
    db.commit()
    db.refresh(boite)

    assert boite.stock == 36  # 3 x 12
