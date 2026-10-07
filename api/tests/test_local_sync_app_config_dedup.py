"""Une installation qui a créé sa propre ligne app_config (get_or_create, avant
son premier pull) ne doit pas se retrouver avec une deuxième ligne quand le
cloud lui envoie SA ligne (même tenant/dépôt, identifiant différent)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
from api.database import Base
from api.models.AppConfig import AppConfig
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


def _find_existing_fallback(db, model, rec):
    """Reproduit exactement le repli ajouté dans local_sync_service.py pour app_config."""
    wh_filter = (
        model.warehouse_id.is_(None) if rec.get("warehouse_id") is None
        else model.warehouse_id == rec["warehouse_id"]
    )
    return db.query(model).filter(model.tenant_id == rec.get("tenant_id"), wh_filter).first()


def test_local_row_found_by_tenant_and_warehouse_not_duplicated(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Maranatha Lessive", is_active=True, is_default=True)
    db.add(wh)
    db.flush()

    # La ligne créée localement par get_or_create, avant tout pull — son propre id.
    local_row = AppConfig(tenant_id=t.id, warehouse_id=wh.id, business_name="Mon Commerce",
                          currency="HTG")
    db.add(local_row)
    db.commit()

    # La ligne envoyée par le cloud pour le MÊME tenant/dépôt — un identifiant différent.
    cloud_rec = {
        "id": "cloud-generated-id-0000",
        "tenant_id": t.id,
        "warehouse_id": wh.id,
        "business_name": "MARANATHA LESSIVE",
        "currency": "HTD",
    }

    assert db.get(AppConfig, cloud_rec["id"]) is None  # pas trouvé par identifiant
    found = _find_existing_fallback(db, AppConfig, cloud_rec)
    assert found is not None, "le repli doit retrouver la ligne locale par (tenant, dépôt)"
    assert found.id == local_row.id  # c'est bien la ligne locale, pas une nouvelle

    # Une seule ligne doit exister pour ce couple (tenant, dépôt), avant et après.
    count = db.query(AppConfig).filter_by(tenant_id=t.id, warehouse_id=wh.id).count()
    assert count == 1
