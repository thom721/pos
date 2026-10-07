"""Une devise modifiée sur le cloud doit être immédiatement visible par
/api/sync/pull-batch pour l'installation du dépôt concerné — sans délai,
indépendamment de tout signal WebSocket."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.requests import Request

import api.models  # noqa: F401
from api.core.dt_coerce import now_local
from api.database import Base
from api.models.AppConfig import AppConfig
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.routes.sync import PullBatchRequest, sync_pull_batch


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


def _req(wh_id):
    return Request({"type": "http", "headers": [(b"x-warehouse-id", wh_id.encode())]})


def test_config_change_visible_immediately_via_pull(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    cfg = AppConfig(tenant_id=t.id, warehouse_id=wh.id, currency="HTG")
    db.add(cfg)
    db.commit()

    # Le PC a déjà synchronisé une fois avant le changement.
    since = (now_local() - timedelta(seconds=5)).isoformat()

    # Modification de la devise, comme le ferait PUT /api/config.
    cfg.currency = "EUR"
    cfg.updated_at = now_local()
    db.commit()

    body = PullBatchRequest(cursors={"app_config": since})
    res = sync_pull_batch(body=body, request=_req(wh.id),
                          claims={"tenant_id": t.id, "tenant_type": "shared"}, db=db)
    records = res["results"]["app_config"]["records"]
    assert records, "la ligne modifiée doit être renvoyée immédiatement"
    assert records[0]["currency"] == "EUR"
