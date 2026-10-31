"""Meme bug que pour ProductPriceTier (voir test_tombstone_product_price_tier.py),
applique a SaleItem : update_sale() supprime les anciennes lignes de vente
(delete-then-recreate) avant d'inserer les nouvelles. Sans tombstone, un
article retire d'une vente deja synchronisee ne disparaissait jamais de
l'autre cote."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.models.Category import Category
from api.models.Product import Product
from api.models.Sale import Sale, SaleStatus
from api.models.SaleItem import SaleItem
from api.models.SyncTombstone import SyncTombstone
from api.schemas.sale import SaleUpdate, SaleItemInput
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
def world(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Maranatha Lessive", is_active=True, is_default=True)
    cat = Category(name="Services", tenant_id=t.id)
    db.add_all([wh, cat])
    db.flush()
    # is_service=True : evite tout passage par record_stock_movement, hors
    # du champ de ce test (deja couvert ailleurs).
    p1 = Product(name="Service A", category_id=cat.id, sale_price=100, tenant_id=t.id, is_service=True)
    p2 = Product(name="Service B", category_id=cat.id, sale_price=200, tenant_id=t.id, is_service=True)
    db.add_all([p1, p2])
    db.flush()

    sale = Sale(
        tenant_id=t.id, user_id=None, warehouse_id=wh.id,
        reference="V-TEST-1", total_amount=300, final_amount=300,
        paid_amount=300, status=SaleStatus.paid,
    )
    db.add(sale)
    db.flush()

    item1 = SaleItem(tenant_id=t.id, sale_id=sale.id, product_id=p1.id,
                      quantity=1, unit_price=100, subtotal=100)
    item2 = SaleItem(tenant_id=t.id, sale_id=sale.id, product_id=p2.id,
                      quantity=1, unit_price=200, subtotal=200)
    db.add_all([item1, item2])
    db.commit()

    return {"tenant": t, "wh": wh, "sale": sale, "item1": item1, "item2": item2, "p1": p1}


def test_update_sale_removing_item_creates_tombstone(db, world):
    """L'admin edite la vente et retire le Service B — la ligne
    correspondante doit laisser une tombstone pour pouvoir se propager."""
    tid, sale, item2, p1 = world["tenant"].id, world["sale"], world["item2"], world["p1"]
    removed_item_id = str(item2.id)

    data = SaleUpdate(
        items=[SaleItemInput(product_id=p1.id, quantity=1, unit_price=100, subtotal=100)],
    )
    sale_service.update_sale(db, sale.id, data, user_id=None, tenant_id=tid)

    remaining = db.query(SaleItem).filter_by(sale_id=sale.id).all()
    assert len(remaining) == 1
    assert str(remaining[0].product_id) == str(p1.id)

    tombstone = (
        db.query(SyncTombstone)
        .filter_by(entity_type="sale_item", record_id=removed_item_id)
        .first()
    )
    assert tombstone is not None, "la ligne de vente retiree doit avoir une tombstone"
