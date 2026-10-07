"""La modification de la devise (PUT /api/config) doit programmer le signal
'sync' au tenant : sinon les installations locales ne sont pas prévenues."""
import asyncio
from types import SimpleNamespace

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.background import BackgroundTasks

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.routes import config as config_route
from api.schemas.config import ConfigUpdate


def test_currency_update_schedules_tenant_notification(monkeypatch):
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.commit()

    calls = []

    async def fake_notify(tenant_id, *args, **kwargs):
        calls.append(tenant_id)

    monkeypatch.setattr(config_route.manager, "notify", fake_notify)

    user = SimpleNamespace(tenant_id=t.id, warehouse_id=[], id="u1")
    bg = BackgroundTasks()
    config_route.update_config(
        data=ConfigUpdate(currency="EUR"),
        background_tasks=bg,
        warehouse_id=None,
        db=db,
        current_user=user,
    )
    # Les tâches d'arrière-plan sont exécutées après la réponse : on les joue ici.
    for task in bg.tasks:
        asyncio.new_event_loop().run_until_complete(task.func(*task.args, **task.kwargs))

    assert calls == [t.id], "la devise modifiée doit prévenir les appareils du tenant"
