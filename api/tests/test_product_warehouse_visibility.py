"""Product.warehouse_id (choisi au formulaire de création produit) était un
champ mort — jamais lu nulle part. Lui donne un vrai sens à la demande de
l'utilisateur : un produit rattaché à UN dépôt précis est masqué de la liste
Produits / recherche Caisse des AUTRES dépôts (produits sans dépôt = NULL
restent visibles partout). L'Entrepôt est explicitement exempté (doit voir
tous les produits pour pouvoir les distribuer)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.Warehouse import Warehouse
from api.services.product_service import ProductService
from api.services import entrepot_service


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


def _make_product(db, tenant, category, name, warehouse_id=None):
    p = Product(name=name, category_id=category.id, sale_price=100,
                purchase_price=50, tenant_id=tenant.id, warehouse_id=warehouse_id)
    db.add(p)
    db.flush()
    return p


def test_product_with_no_warehouse_visible_everywhere(db, tenant, category, two_depots):
    depot_a, depot_b = two_depots
    _make_product(db, tenant, category, "Partagé", warehouse_id=None)

    svc = ProductService(db, tenant_id=tenant.id)
    names_a = {p.name for p in svc.list(per_page=10, warehouse_id=depot_a.id)["data"]}
    names_b = {p.name for p in svc.list(per_page=10, warehouse_id=depot_b.id)["data"]}
    assert "Partagé" in names_a
    assert "Partagé" in names_b


def test_product_restricted_to_one_warehouse_hidden_from_other(db, tenant, category, two_depots):
    depot_a, depot_b = two_depots
    _make_product(db, tenant, category, "Exclusif A", warehouse_id=depot_a.id)

    svc = ProductService(db, tenant_id=tenant.id)
    names_a = {p.name for p in svc.list(per_page=10, warehouse_id=depot_a.id)["data"]}
    names_b = {p.name for p in svc.list(per_page=10, warehouse_id=depot_b.id)["data"]}
    assert "Exclusif A" in names_a
    assert "Exclusif A" not in names_b


def test_no_warehouse_context_shows_everything(db, tenant, category, two_depots):
    """« Tous les business » (pas de dépôt actif) → vue globale, rien masqué."""
    depot_a, _ = two_depots
    _make_product(db, tenant, category, "Exclusif A", warehouse_id=depot_a.id)

    svc = ProductService(db, tenant_id=tenant.id)
    names = {p.name for p in svc.list(per_page=10)["data"]}
    assert "Exclusif A" in names


def test_entrepot_sees_all_products_regardless_of_assignment(db, tenant, category, two_depots):
    depot_a, depot_b = two_depots
    _make_product(db, tenant, category, "Exclusif A", warehouse_id=depot_a.id)
    _make_product(db, tenant, category, "Exclusif B", warehouse_id=depot_b.id)
    entrepot = entrepot_service.create_entrepot(db, tenant.id)

    svc = ProductService(db, tenant_id=tenant.id)
    names = {p.name for p in svc.list(per_page=10, warehouse_id=entrepot.id, restrict_to_warehouse=False)["data"]}
    assert "Exclusif A" in names
    assert "Exclusif B" in names
