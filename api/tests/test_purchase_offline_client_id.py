"""Un achat créé hors-ligne doit recevoir le MÊME id que celui généré par
l'app (client_id) — même mécanisme que Sale.client_id / Customer.client_id.
Sans ça, un rejeu (réseau revenu, ou retenté manuellement côté bureau/web
qui n'avait jusqu'ici aucune protection) créait un second achat en double,
sans idempotence possible."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.schemas.purchase import PurchaseCreate, PurchaseItemInput
from api.services.purchase_service import create_purchase


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
def product(db, tenant):
    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    p = Product(name="Produit", category_id=cat.id, sale_price=100, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    return p


def _purchase_data(product, client_id=None):
    return PurchaseCreate(
        client_id=client_id,
        paid_amount=100,
        total_amount=100,
        items=[PurchaseItemInput(
            product_id=product.id, ordered_qty=1, remaining_qty=1, unit_price=100,
        )],
    )


def test_client_id_becomes_the_purchase_id(db, tenant, product):
    client_id = "11111111-1111-1111-1111-111111111111"
    data = _purchase_data(product, client_id=client_id)

    purchase = create_purchase(db, data, user_id="u1", tenant_id=tenant.id)

    assert purchase.id == client_id


def test_retry_with_same_client_id_is_idempotent(db, tenant, product):
    """Rejeu de la même création (réponse perdue côté réseau, ou l'app
    bureau qui retente après un message d'erreur générique) — doit
    renvoyer l'achat déjà créé, pas en créer un second."""
    client_id = "22222222-2222-2222-2222-222222222222"
    data = _purchase_data(product, client_id=client_id)

    first = create_purchase(db, data, user_id="u1", tenant_id=tenant.id)
    second = create_purchase(db, data, user_id="u1", tenant_id=tenant.id)

    assert first.id == second.id == client_id


def test_no_client_id_generates_a_random_id(db, tenant, product):
    """Achat en ligne classique (pas de client_id fourni) — inchangé."""
    data = _purchase_data(product, client_id=None)

    purchase = create_purchase(db, data, user_id="u1", tenant_id=tenant.id)

    assert purchase.id is not None and purchase.id != ""
