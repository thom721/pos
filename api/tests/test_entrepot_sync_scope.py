"""Un entrepôt (Warehouse.is_entrepot=True) sans linked_warehouse_id doit
rester cloud-only : /api/sync/pull et /api/sync/pull-batch ne doivent jamais
le renvoyer à une installation locale — sinon deux installations peuvent
créer chacune leur propre entrepôt "Entrepôt" indépendamment (même nom, id
différent), sans jamais se fusionner côté sync (pas de fallback de matching
par nom pour warehouse). Un entrepôt rattaché à un dépôt (linked_warehouse_id
défini) doit, lui, synchroniser normalement."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.routes.sync import sync_pull, sync_pull_batch, PullBatchRequest


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


def _claims(tenant_id):
    return {"tenant_id": tenant_id, "tenant_type": "shared"}


def test_pull_excludes_unlinked_entrepot(db, tenant):
    depot = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(depot)
    db.flush()

    unlinked = Warehouse(tenant_id=tenant.id, name="Entrepôt libre", is_entrepot=True, is_claimed=True)
    linked = Warehouse(tenant_id=tenant.id, name="Entrepôt lié", is_entrepot=True,
                        is_claimed=True, linked_warehouse_id=depot.id)
    db.add_all([unlinked, linked])
    db.commit()

    result = sync_pull(entity_type="warehouse", since="1970-01-01T00:00:00",
                        claims=_claims(tenant.id), db=db)

    ids = {r["id"] for r in result["records"]}
    assert depot.id in ids
    assert linked.id in ids
    assert unlinked.id not in ids


def test_pull_batch_excludes_unlinked_entrepot(db, tenant):
    depot = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(depot)
    db.flush()

    unlinked = Warehouse(tenant_id=tenant.id, name="Entrepôt libre", is_entrepot=True, is_claimed=True)
    linked = Warehouse(tenant_id=tenant.id, name="Entrepôt lié", is_entrepot=True,
                        is_claimed=True, linked_warehouse_id=depot.id)
    db.add_all([unlinked, linked])
    db.commit()

    body = PullBatchRequest(cursors={"warehouse": "1970-01-01T00:00:00"})
    result = sync_pull_batch(body=body, claims=_claims(tenant.id), db=db)

    ids = {r["id"] for r in result["results"]["warehouse"]["records"]}
    assert depot.id in ids
    assert linked.id in ids
    assert unlinked.id not in ids


def test_regular_warehouse_never_filtered(db, tenant):
    """Sanity : le filtre ne s'applique qu'aux entrepôts (is_entrepot=True),
    jamais aux dépôts classiques (is_entrepot=False, linked_warehouse_id
    toujours NULL pour eux)."""
    depot = Warehouse(tenant_id=tenant.id, name="Dépôt seul", is_active=True, is_default=True)
    db.add(depot)
    db.commit()

    result = sync_pull(entity_type="warehouse", since="1970-01-01T00:00:00",
                        claims=_claims(tenant.id), db=db)

    ids = {r["id"] for r in result["records"]}
    assert depot.id in ids
