"""Suppression complète d'un tenant (admin) : doit nettoyer TOUTES ses
données sans jamais toucher aux autres tenants. Le test le plus important
ici est test_tenant_scoped_models_list_is_complete — il échoue si un futur
modèle avec tenant_id est ajouté sans être ajouté à TENANT_SCOPED_MODELS,
ce qui laisserait sinon des données orphelines silencieusement."""
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401 — assure que tous les modèles sont importés
from api.database import Base
from api.models.AuditLog import AuditLog
from api.models.Category import Category
from api.models.Customer import Customer
from api.models.Debt import Debt
from api.models.Discount import Discount, DiscountType
from api.models.PosRegister import PosRegister
from api.models.Product import Product
from api.models.Sale import Sale, SaleStatus
from api.models.SaleItem import SaleItem
from api.models.StockMovement import StockMovement, StockType
from api.models.Supplier import Supplier
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.services.tenant_deletion_service import (
    TENANT_SCOPED_MODELS,
    delete_tenant_completely,
)


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


def _seed_tenant(db, slug):
    """Crée un tenant avec une ligne dans chacune des tables 'core' testées
    directement — retourne le tenant pour usage ultérieur."""
    tenant = Tenant(business_name=f"T-{slug}", owner_email=f"{slug}@t.com", slug=slug)
    db.add(tenant)
    db.flush()

    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()

    user = User(fname="U", lname=slug, username=f"u-{slug}", email=f"u-{slug}@t.com",
                password="x", tenant_id=tenant.id, roles=["cashier"], permissions=[],
                is_active=True)
    db.add(user)

    cat = Category(name=f"Cat-{slug}", tenant_id=tenant.id)
    db.add(cat)
    db.flush()

    product = Product(name=f"Produit-{slug}", category_id=cat.id, sale_price=100,
                       purchase_price=50, tenant_id=tenant.id)
    db.add(product)

    customer = Customer(name=f"Client-{slug}", tenant_id=tenant.id, phone="12345678",
                        address="Adresse test")
    db.add(customer)

    supplier = Supplier(name=f"Fournisseur-{slug}", tenant_id=tenant.id, phone="12345678",
                        address="Adresse test")
    db.add(supplier)

    register = PosRegister(tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse",
                            is_active=True)
    db.add(register)

    discount = Discount(tenant_id=tenant.id, name=f"Rabais-{slug}",
                         type=DiscountType.percentage, value=10)
    db.add(discount)

    audit = AuditLog(tenant_id=tenant.id, action="CREATE", resource_type="product")
    db.add(audit)

    db.flush()

    sale = Sale(tenant_id=tenant.id, user_id=user.id, warehouse_id=wh.id,
                reference=f"REF-{slug}", total_amount=100, final_amount=100,
                paid_amount=100, status=SaleStatus.paid)
    db.add(sale)
    db.flush()

    sale_item = SaleItem(tenant_id=tenant.id, sale_id=sale.id, product_id=product.id,
                          quantity=1, unit_price=100, subtotal=100)
    db.add(sale_item)

    movement = StockMovement(tenant_id=tenant.id, product_id=product.id,
                              warehouse_id=wh.id, type=StockType.in_, quantity=10)
    db.add(movement)

    debt = Debt(tenant_id=tenant.id, total_amount=50, balance=50, status="UNPAID",
                reference_type="SALE", reference_id=sale.id,
                partner_type="CUSTOMER", partner_id=customer.id)
    db.add(debt)

    db.commit()
    return tenant


_CORE_MODELS = [Warehouse, User, Category, Product, Customer, Supplier,
                PosRegister, Discount, AuditLog, Sale, SaleItem, StockMovement, Debt]


def _core_counts(db, tenant_id) -> dict:
    return {
        m.__tablename__: db.query(m).filter(m.tenant_id == tenant_id).count()
        for m in _CORE_MODELS
    }


def test_delete_tenant_removes_all_core_data(db):
    tenant = _seed_tenant(db, "acme")
    before = _core_counts(db, tenant.id)
    assert all(n > 0 for n in before.values()), before  # sanity : tout a bien été créé

    counts = delete_tenant_completely(db, tenant.id)

    after = _core_counts(db, tenant.id)
    assert all(n == 0 for n in after.values()), after
    assert db.get(Tenant, tenant.id) is None
    for table in before:
        assert counts[table] == before[table]


def test_delete_tenant_never_touches_other_tenants(db):
    tenant_a = _seed_tenant(db, "acme")
    tenant_b = _seed_tenant(db, "beta")
    before_b = _core_counts(db, tenant_b.id)

    delete_tenant_completely(db, tenant_a.id)

    after_b = _core_counts(db, tenant_b.id)
    assert after_b == before_b
    assert db.get(Tenant, tenant_b.id) is not None
    assert db.get(Tenant, tenant_a.id) is None


def test_delete_nonexistent_tenant_returns_none(db):
    assert delete_tenant_completely(db, "does-not-exist") is None


def test_delete_tenant_scans_all_scoped_models_and_finds_none(db):
    """Après suppression, AUCUNE des ~49 tables tenant_id-scopées ne contient
    plus de ligne pour ce tenant — pas seulement les tables 'core' testées
    explicitement ci-dessus."""
    tenant = _seed_tenant(db, "acme")
    delete_tenant_completely(db, tenant.id)
    for model in TENANT_SCOPED_MODELS:
        remaining = db.query(model).filter(model.tenant_id == tenant.id).count()
        assert remaining == 0, f"{model.__tablename__} a encore {remaining} ligne(s)"


def test_tenant_scoped_models_list_is_complete():
    """Garde-fou : si un nouveau modèle avec tenant_id est ajouté au projet
    sans être ajouté à TENANT_SCOPED_MODELS, delete_tenant_completely
    laisserait ses données orphelines après suppression d'un tenant — ce
    test échoue immédiatement dans ce cas plutôt que de laisser filer une
    fuite de données silencieuse en production."""
    known_tables = {m.__tablename__ for m in TENANT_SCOPED_MODELS}
    missing = []
    for mapper in Base.registry.mappers:
        cls = mapper.class_
        if cls.__tablename__ in ("tenants", "platform_config", "sync_state"):
            continue
        if hasattr(cls, "tenant_id") and cls.__tablename__ not in known_tables:
            missing.append(f"{cls.__name__} ({cls.__tablename__})")
    assert missing == [], (
        "Modèle(s) avec tenant_id absent(s) de TENANT_SCOPED_MODELS : "
        + ", ".join(missing)
    )
