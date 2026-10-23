"""GET /api/reports/quantity-by-category — quantite vendue par produit
(SaleItem.quantity, pas les mouvements de stock : pour un produit compose,
c'est donc en unites "caisse" telles que reellement vendues, pas en unites
du composant), groupee par categorie avec sous-totaux, pour un relevé de
clôture style grossiste (demande explicite : reproduire l'esprit du rapport
Secom Haiti fourni par l'utilisateur)."""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import api.models  # noqa: F401
import api.main as main_module
from api.database import Base, get_db
from api.core.security import create_access_token
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Category import Category
from api.models.Product import Product
from api.models.Warehouse import Warehouse
from api.models.StockMovement import StockMovement, StockType
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False},
                            poolclass=StaticPool)
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def client(db):
    def _override_get_db():
        yield db
    main_module.app.dependency_overrides[get_db] = _override_get_db
    with TestClient(main_module.app, raise_server_exceptions=True) as c:
        yield c
    main_module.app.dependency_overrides.clear()


@pytest.fixture()
def tenant(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    return t


@pytest.fixture()
def admin_token(db, tenant):
    user = User(
        fname="Admin", lname="Test", username="admin_test",
        email="admin_test@t.com", password="x", tenant_id=tenant.id,
        roles=["admin"], permissions=["all"], is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return create_access_token({"sub": user.id, "perm_v": user.permissions_version or 0})


@pytest.fixture()
def categories(db, tenant):
    boissons = Category(name="Boissons", tenant_id=tenant.id)
    hygiene = Category(name="Hygiène", tenant_id=tenant.id)
    db.add_all([boissons, hygiene])
    db.flush()
    return boissons, hygiene


@pytest.fixture()
def depot(db, tenant):
    w = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(w)
    db.flush()
    return w


def test_quantity_grouped_by_category_with_subtotals(
    db, client, tenant, admin_token, categories, depot,
):
    boissons, hygiene = categories
    coca = Product(name="Coca Cola", category_id=boissons.id, sale_price=10, tenant_id=tenant.id)
    fanta = Product(name="Fanta", category_id=boissons.id, sale_price=10, tenant_id=tenant.id)
    savon = Product(name="Savon", category_id=hygiene.id, sale_price=5, tenant_id=tenant.id)
    db.add_all([coca, fanta, savon])
    db.flush()
    for p in (coca, fanta, savon):
        db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=100,
                              tenant_id=tenant.id, warehouse_id=depot.id))
    db.commit()

    sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=10 * 3 + 10 * 5 + 5 * 2, payment_method="CASH", warehouse_id=depot.id,
            items=[
                SaleItemInput(product_id=coca.id, quantity=3, unit_price=10, subtotal=30),
                SaleItemInput(product_id=fanta.id, quantity=5, unit_price=10, subtotal=50),
                SaleItemInput(product_id=savon.id, quantity=2, unit_price=5, subtotal=10),
            ],
        ),
        user_id="u1", tenant_id=tenant.id, current_user=None,
    )
    db.commit()

    res = client.get(
        "/api/reports/quantity-by-category",
        headers={"Authorization": f"Bearer {admin_token}"},
    )

    assert res.status_code == 200
    data = res.json()
    assert data["grand_total_qty"] == 10
    assert data["grand_total_lines"] == 3

    by_name = {c["category_name"]: c for c in data["categories"]}
    assert by_name["Boissons"]["subtotal_qty"] == 8
    assert {i["product_name"] for i in by_name["Boissons"]["items"]} == {"Coca Cola", "Fanta"}
    assert by_name["Hygiène"]["subtotal_qty"] == 2


def test_services_excluded_from_quantity_report(
    db, client, tenant, admin_token, categories, depot,
):
    """Bug reel : un service (ex: "Entretien Veste") apparaissait dans ce
    relevé alors qu'aucune marchandise physique n'avait de sens a y
    associer une quantite/stock — ce rapport reproduit un ledger de
    mouvement de marchandise (style grossiste), pas une liste de toutes
    les lignes de vente."""
    boissons, hygiene = categories
    coca = Product(name="Coca Cola", category_id=boissons.id, sale_price=10, tenant_id=tenant.id)
    entretien = Product(name="Entretien Veste", category_id=hygiene.id, sale_price=20,
                         tenant_id=tenant.id, is_service=True)
    db.add_all([coca, entretien])
    db.flush()
    db.add(StockMovement(product_id=coca.id, type=StockType.in_, quantity=100,
                          tenant_id=tenant.id, warehouse_id=depot.id))
    db.commit()

    sale_service.create_sale(
        db,
        SaleCreate(
            paid_amount=10 * 3 + 20, payment_method="CASH", warehouse_id=depot.id,
            items=[
                SaleItemInput(product_id=coca.id, quantity=3, unit_price=10, subtotal=30),
                SaleItemInput(product_id=entretien.id, quantity=1, unit_price=20, subtotal=20),
            ],
        ),
        user_id="u1", tenant_id=tenant.id, current_user=None,
    )
    db.commit()

    res = client.get(
        "/api/reports/quantity-by-category",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["grand_total_qty"] == 3
    assert data["grand_total_lines"] == 1
    names = {i["product_name"] for c in data["categories"] for i in c["items"]}
    assert "Entretien Veste" not in names
