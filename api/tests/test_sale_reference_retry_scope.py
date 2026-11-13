"""La boucle de retry de create_sale (jusqu'a 5 tentatives) n'a de sens que
pour une vraie collision de numero de recu (contrainte unique reference/
tenant/warehouse, rare : deux ventes quasi simultanees). Avant ce correctif,
elle retentait aussi bêtement 5 fois pour N'IMPORTE QUELLE IntegrityError —
ex: un customer_id orphelin (client jamais cree cote cloud, incident reel
vu en prod) — alors que recalculer un nouveau numero de recu ne resout
jamais ce genre d'erreur. _is_reference_collision() distingue les deux."""
from decimal import Decimal
from types import SimpleNamespace

import pytest
from sqlalchemy import create_engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Category import Category
from api.models.Product import Product
from api.models.Sale import Sale
from api.models.StockMovement import StockMovement, StockType
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.schemas.sale import SaleCreate, SaleItemInput
from api.services import sale_service
from api.services.sale_service import _is_reference_collision


def _fake_integrity_error(message: str) -> IntegrityError:
    return IntegrityError("stmt", {}, Exception(message))


def test_is_reference_collision_true_for_mysql_duplicate_entry():
    exc = _fake_integrity_error(
        "(1062, \"Duplicate entry 'VNT-00001-t-wh' for key 'sales.uq_sale_ref_tenant_warehouse'\")"
    )
    assert _is_reference_collision(exc) is True


def test_is_reference_collision_true_for_sqlite_unique_constraint():
    exc = _fake_integrity_error(
        "UNIQUE constraint failed: sales.reference, sales.tenant_id, sales.warehouse_id"
    )
    assert _is_reference_collision(exc) is True


def test_is_reference_collision_false_for_foreign_key_violation():
    exc = _fake_integrity_error(
        "(1452, 'Cannot add or update a child row: a foreign key constraint fails "
        "(`post_db`.`sales`, CONSTRAINT `sales_ibfk_2` FOREIGN KEY (`customer_id`) "
        "REFERENCES `customers` (`id`))')"
    )
    assert _is_reference_collision(exc) is False


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


@pytest.fixture()
def world(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Dépôt", is_active=True, is_default=True)
    cat = Category(name="Cat", tenant_id=t.id)
    db.add_all([wh, cat])
    db.flush()
    p = Product(name="Produit", category_id=cat.id, sale_price=100, tenant_id=t.id)
    db.add(p)
    db.flush()
    db.add(StockMovement(product_id=p.id, type=StockType.in_, quantity=10,
                          tenant_id=t.id, warehouse_id=wh.id))
    db.commit()
    return t, wh, p


def _sale_data(product, warehouse_id, customer_id=None):
    return SaleCreate(
        customer_id=customer_id,
        paid_amount=100, payment_method="CASH", warehouse_id=warehouse_id,
        items=[SaleItemInput(product_id=product.id, quantity=1, unit_price=100, subtotal=100)],
    )


def test_unrelated_integrity_error_raises_without_retrying(db, world, monkeypatch):
    """customer_id orphelin (FK vers un client inexistant) — meme bug que
    l'incident reel : doit echouer IMMEDIATEMENT (1 seul calcul de
    reference), pas apres 5 tentatives inutiles. SQLite ne fait pas
    respecter les FK par defaut (PRAGMA foreign_keys desactive ici, comme
    dans le reste de la suite) — on simule donc directement l'IntegrityError
    telle qu'observee en reel (MySQL, errno 1452) via db.flush, plutot que
    de compter sur une vraie violation de contrainte."""
    tenant, wh, product = world
    calls = {"n": 0}
    real_next_ref = sale_service._next_sale_reference

    def _spy(*args, **kwargs):
        calls["n"] += 1
        return real_next_ref(*args, **kwargs)

    monkeypatch.setattr(sale_service, "_next_sale_reference", _spy)

    # D'autres appels internes (price_tier_service, etc.) flushent peut-etre
    # AVANT d'atteindre la boucle de retry — seul le flush qui suit un appel
    # a _next_sale_reference (celui de l'insertion de la Sale elle-meme) doit
    # declencher la fausse erreur.
    real_flush = db.flush

    def _fake_flush(*args, **kwargs):
        if calls["n"] >= 1:
            raise IntegrityError("INSERT INTO sales ...", {}, Exception(
                "(1452, 'Cannot add or update a child row: a foreign key constraint fails "
                "(`post_db`.`sales`, CONSTRAINT `sales_ibfk_2` FOREIGN KEY (`customer_id`) "
                "REFERENCES `customers` (`id`))')"
            ))
        return real_flush(*args, **kwargs)

    monkeypatch.setattr(db, "flush", _fake_flush)

    with pytest.raises(IntegrityError):
        sale_service.create_sale(
            db, _sale_data(product, wh.id), user_id="u1", tenant_id=tenant.id,
        )

    assert calls["n"] == 1, "une erreur sans rapport avec le numero de recu ne doit jamais etre retentee"


def test_genuine_reference_collision_still_retries_and_succeeds(db, world, monkeypatch):
    """Non-regression : une vraie collision de numero (deux ventes quasi
    simultanees) doit toujours retenter avec un nouveau numero, pas
    echouer immediatement."""
    tenant, wh, product = world
    real_next_ref = sale_service._next_sale_reference
    calls = {"n": 0}

    def _collide_once(*args, **kwargs):
        calls["n"] += 1
        if calls["n"] == 1:
            return "VNT-00001"  # collision volontaire avec la vente deja existante ci-dessous
        return real_next_ref(*args, **kwargs)

    db.add(Sale(tenant_id=tenant.id, warehouse_id=wh.id, user_id="u1",
                reference="VNT-00001", total_amount=10, final_amount=10, paid_amount=10))
    db.commit()

    monkeypatch.setattr(sale_service, "_next_sale_reference", _collide_once)

    sale = sale_service.create_sale(
        db, _sale_data(product, wh.id), user_id="u1", tenant_id=tenant.id,
    )
    db.commit()

    assert calls["n"] == 2, "doit avoir retente une fois apres la collision"
    assert sale.reference == "VNT-00002"
