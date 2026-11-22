"""ProductService.list() doit renvoyer "pages" — sans ce champ,
PaginatedResponse.fromJson (Flutter) retombait sur pages=1 par défaut, donc
_fetchAllProductsForPicker() (sélecteur de produit composant, utilisé aussi
par /api/entrepot/{id}/products et /api/sales/products/search) s'arrêtait
toujours après la 1re page de 100 produits — tout produit au-delà restait
invisible dans la recherche, pour un tenant en ayant plus de 100 (cas réel :
client ne trouvant pas "Sprite" parmi 180 produits)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.services.product_service import ProductService


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


def _seed(db, tenant, category, count):
    for i in range(count):
        db.add(Product(name=f"Produit {i:03d}", category_id=category.id,
                        sale_price=10, tenant_id=tenant.id))
    db.commit()


def test_pages_is_one_when_everything_fits_on_one_page(db, tenant, category):
    _seed(db, tenant, category, 5)
    result = ProductService(db, tenant_id=tenant.id).list(per_page=100)
    assert result["total"] == 5
    assert result["pages"] == 1


def test_pages_rounds_up_when_total_is_not_a_multiple_of_per_page(db, tenant, category):
    _seed(db, tenant, category, 180)
    result = ProductService(db, tenant_id=tenant.id).list(per_page=100)
    assert result["total"] == 180
    assert result["pages"] == 2


def test_second_page_reaches_products_past_the_first_hundred(db, tenant, category):
    # Reproduit le cas réel : un produit nommé après les 100 premiers (donc
    # hors de la 1re page) doit rester atteignable via page=2.
    _seed(db, tenant, category, 150)
    first_page = ProductService(db, tenant_id=tenant.id).list(page=1, per_page=100)
    second_page = ProductService(db, tenant_id=tenant.id).list(page=2, per_page=100)
    assert len(first_page["data"]) == 100
    assert len(second_page["data"]) == 50
    all_names = {p.name for p in first_page["data"]} | {p.name for p in second_page["data"]}
    assert len(all_names) == 150
