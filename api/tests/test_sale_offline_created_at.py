"""Une vente créée hors-ligne doit garder la date/heure réelle de la
transaction, même si elle ne synchronise avec le serveur que des heures ou
des jours plus tard — sinon "ventes du jour", rapports et la fenêtre de
rapprochement de caisse (session.opened_at → maintenant) sont faussés par
des ventes qui prennent la date DE LA SYNCHRO au lieu de la date réelle."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
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
def warehouse(db, tenant):
    w = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(w)
    db.flush()
    return w


@pytest.fixture()
def product(db, tenant, category, warehouse):
    p = Product(name="Produit", category_id=category.id, sale_price=100, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10,
                          tenant_id=tenant.id, warehouse_id=warehouse.id))
    db.commit()
    return p


def _sale_data(product, warehouse_id, created_at=None):
    return SaleCreate(
        paid_amount=100,
        payment_method="CASH",
        warehouse_id=warehouse_id,
        created_at=created_at,
        items=[SaleItemInput(product_id=product.id, quantity=1, unit_price=100, subtotal=100)],
    )


def test_offline_created_at_is_preserved(db, tenant, product, warehouse):
    yesterday = now_local() - timedelta(days=1)
    data = _sale_data(product, warehouse.id, created_at=yesterday.isoformat())

    sale = sale_service.create_sale(db, data, user_id="u1", tenant_id=tenant.id)
    db.commit()

    assert sale.created_at.date() == yesterday.date()


def test_no_created_at_falls_back_to_now(db, tenant, product, warehouse):
    """Vente en ligne classique (pas de created_at fourni) — inchangé :
    l'horodatage par défaut du modèle (now_local() à l'insertion) s'applique."""
    data = _sale_data(product, warehouse.id, created_at=None)

    sale = sale_service.create_sale(db, data, user_id="u1", tenant_id=tenant.id)
    db.commit()

    assert sale.created_at.date() == now_local().date()


def test_malformed_created_at_falls_back_to_now(db, tenant, product, warehouse):
    """Une string invalide (bug client, corruption) ne doit jamais faire
    planter la vente — parse_dt renvoie None, le défaut du modèle s'applique."""
    data = _sale_data(product, warehouse.id, created_at="not-a-date")

    sale = sale_service.create_sale(db, data, user_id="u1", tenant_id=tenant.id)
    db.commit()

    assert sale.created_at.date() == now_local().date()
