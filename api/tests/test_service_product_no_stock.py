"""Un produit marqué `is_service` (ex: pressing, lessive) n'a ni stock ni
quantité disponible à vérifier — create_sale/cancel_sale doivent l'ignorer
entièrement côté mouvements de stock (voir api/models/Product.py)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.StockMovement import StockMovement
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
def pressing(db, tenant, category):
    p = Product(
        name="Pressing chemise", category_id=category.id, sale_price=250,
        tenant_id=tenant.id, is_service=True,
    )
    db.add(p)
    db.flush()
    return p


def _sale_data(product, quantity):
    return SaleCreate(
        paid_amount=250 * quantity,
        payment_method="CASH",
        items=[SaleItemInput(
            product_id=product.id, quantity=quantity, unit_price=250,
            subtotal=250 * quantity,
        )],
    )


def test_service_sale_allowed_with_zero_stock(db, tenant, pressing):
    """Aucun StockMovement n'existe pour ce produit — une vente classique
    (non-service) serait rejetée pour stock insuffisant ; un service passe."""
    assert pressing.available_quantity == 0

    sale = sale_service.create_sale(
        db, _sale_data(pressing, 3), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()
    assert sale is not None
    assert db.query(StockMovement).filter_by(product_id=pressing.id).count() == 0


def test_service_sale_cancel_creates_no_stock_movement(db, tenant, pressing):
    sale = sale_service.create_sale(
        db, _sale_data(pressing, 2), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()

    sale_service.cancel_sale(db, sale.id, user_id="u1", tenant_id=tenant.id)
    db.commit()

    assert db.query(StockMovement).filter_by(product_id=pressing.id).count() == 0
