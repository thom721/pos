"""Alerte email stock bas (AppConfig.low_stock_alert_enabled/_roles) : envoyée
une seule fois au franchissement du seuil (Product.alert_stock) vers le bas,
pas à chaque vente supplémentaire une fois déjà sous le seuil — voir
stock_service.record_stock_movement / api.utils.email.maybe_send_low_stock_alert."""
import json

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
import api.utils.email as email_module
from api.database import Base
from api.models.AppConfig import AppConfig
from api.models.Category import Category
from api.models.PlatformConfig import PlatformConfig
from api.models.Product import Product
from api.models.StockMovement import StockType
from api.models.Tenant import Tenant
from api.models.User import User
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
def tenant(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.add(PlatformConfig(smtp_host="smtp.example.com", smtp_from="noreply@example.com"))
    db.flush()
    return t


@pytest.fixture()
def category(db, tenant):
    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    return cat


@pytest.fixture()
def product(db, tenant, category):
    p = Product(name="Produit", category_id=category.id, sale_price=100,
                purchase_price=50, tenant_id=tenant.id, alert_stock=5)
    db.add(p)
    db.flush()
    return p


def _enable_alert(db, tenant, roles=("admin",)):
    db.add(AppConfig(tenant_id=tenant.id, low_stock_alert_enabled=True,
                      low_stock_alert_roles=json.dumps(list(roles))))
    db.flush()


def _make_user(db, tenant, roles, email="admin@t.com"):
    u = User(fname="U", lname="Test", username=f"u{email}", email=email,
             password="x", tenant_id=tenant.id, roles=roles,
             permissions=[], is_active=True)
    db.add(u)
    db.commit()
    return u


def _capture_sent(monkeypatch):
    sent = []
    monkeypatch.setattr(email_module, "send_low_stock_email",
                         lambda **kw: sent.append(kw))
    return sent


def test_alert_sent_on_threshold_crossing(db, tenant, product, monkeypatch):
    _enable_alert(db, tenant)
    _make_user(db, tenant, ["admin"])
    sent = _capture_sent(monkeypatch)

    record_stock_movement(db, product_id=product.id, quantity=10,
                           type=StockType.in_, tenant_id=tenant.id)
    db.commit()
    assert sent == []  # stock monte, jamais d'alerte

    record_stock_movement(db, product_id=product.id, quantity=-6,
                           type=StockType.out, tenant_id=tenant.id)
    db.commit()
    assert len(sent) == 1
    assert sent[0]["to_addr"] == "admin@t.com"
    assert sent[0]["product_name"] == "Produit"


def test_alert_not_resent_while_already_below_threshold(db, tenant, product, monkeypatch):
    _enable_alert(db, tenant)
    _make_user(db, tenant, ["admin"])
    sent = _capture_sent(monkeypatch)

    record_stock_movement(db, product_id=product.id, quantity=8,
                           type=StockType.in_, tenant_id=tenant.id)
    db.commit()
    record_stock_movement(db, product_id=product.id, quantity=-4,
                           type=StockType.out, tenant_id=tenant.id)
    db.commit()
    assert len(sent) == 1  # franchissement 8 -> 4 (<= seuil 5)

    record_stock_movement(db, product_id=product.id, quantity=-1,
                           type=StockType.out, tenant_id=tenant.id)
    db.commit()
    assert len(sent) == 1  # toujours sous le seuil, pas de 2e email


def test_alert_disabled_by_default(db, tenant, product, monkeypatch):
    """AppConfig par défaut (jamais créé/activé) — aucune alerte, même en
    franchissant réellement le seuil."""
    _make_user(db, tenant, ["admin"])
    sent = _capture_sent(monkeypatch)

    record_stock_movement(db, product_id=product.id, quantity=8,
                           type=StockType.in_, tenant_id=tenant.id)
    db.commit()
    record_stock_movement(db, product_id=product.id, quantity=-4,
                           type=StockType.out, tenant_id=tenant.id)
    db.commit()
    assert sent == []


def test_alert_only_sent_to_configured_roles(db, tenant, product, monkeypatch):
    _enable_alert(db, tenant, roles=["manager"])
    _make_user(db, tenant, ["cashier"], email="cashier@t.com")
    _make_user(db, tenant, ["manager"], email="manager@t.com")
    sent = _capture_sent(monkeypatch)

    record_stock_movement(db, product_id=product.id, quantity=8,
                           type=StockType.in_, tenant_id=tenant.id)
    db.commit()
    record_stock_movement(db, product_id=product.id, quantity=-4,
                           type=StockType.out, tenant_id=tenant.id)
    db.commit()

    assert len(sent) == 1
    assert sent[0]["to_addr"] == "manager@t.com"


def test_alert_skipped_without_smtp_configured(db, tenant, product, monkeypatch):
    db.query(PlatformConfig).first().smtp_host = ""
    _enable_alert(db, tenant)
    _make_user(db, tenant, ["admin"])
    sent = _capture_sent(monkeypatch)

    record_stock_movement(db, product_id=product.id, quantity=8,
                           type=StockType.in_, tenant_id=tenant.id)
    db.commit()
    record_stock_movement(db, product_id=product.id, quantity=-4,
                           type=StockType.out, tenant_id=tenant.id)
    db.commit()
    assert sent == []
