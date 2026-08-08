"""Test HTTP de bout en bout (TestClient, pas seulement le service) pour
l'entrepôt. Un bug de schéma de réponse (response_model) n'est invisible que
si on appelle le service directement — la suite de tests de ce projet est
sinon 100% service-level, ce qui a laissé passer un vrai bug en production
(GET /api/entrepot/products renvoyait 500 : response_model utilisait le
PaginatedResponse "meta"-wrappé de schemas/common.py au lieu du
PaginatedResponse plat de core/PaginateHelper.py que ProductService.list()
renvoie réellement — voir api/routes/entrepot.py)."""
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import api.models  # noqa: F401
from api.database import Base, get_db
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Category import Category
from api.models.Product import Product
from api.core.security import create_access_token
import api.main as main_module


@pytest.fixture()
def engine():
    # StaticPool + check_same_thread=False : le TestClient exécute les
    # requêtes dans un thread différent de celui du test — une base SQLite
    # :memory: normale est isolée par connexion/thread, il faut donc forcer
    # une connexion unique partagée.
    return create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )


@pytest.fixture()
def db(engine):
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def client(engine):
    TestSession = sessionmaker(bind=engine)

    def _override_get_db():
        db = TestSession()
        try:
            yield db
        finally:
            db.close()

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
    token = create_access_token({"sub": user.id, "perm_v": user.permissions_version or 0})
    return token


@pytest.fixture()
def product(db, tenant):
    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    p = Product(name="Produit", category_id=cat.id, sale_price=100,
                purchase_price=50, tenant_id=tenant.id)
    db.add(p)
    db.commit()
    return p


def test_get_entrepot_products_returns_200_with_valid_shape(client, admin_token, tenant, product):
    """Reproduit exactement le bug trouvé en test manuel : créer l'entrepôt
    puis lister ses produits ne doit pas lever de ResponseValidationError."""
    headers = {"Authorization": f"Bearer {admin_token}"}

    create_res = client.post("/api/entrepot/", json={"name": "Entrepôt"}, headers=headers)
    assert create_res.status_code == 201, create_res.text
    entrepot_id = create_res.json()["id"]

    res = client.get(f"/api/entrepot/{entrepot_id}/products", params={"page": 1, "per_page": 20}, headers=headers)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["page"] == 1
    assert body["per_page"] == 20
    assert body["total"] == 1
    assert body["data"][0]["name"] == "Produit"
