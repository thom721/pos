"""Vérifie que change_due/loyalty_earned/loyalty_redeemed (ajoutés à Sale pour
la monnaie rendue et la fidélisation) traversent bien la synchronisation
local↔cloud sans câblage supplémentaire : `_row_to_dict`/`_serialize` et la
boucle de pull dans local_sync_service dérivent leurs champs dynamiquement
des colonnes SQLAlchemy du modèle (`sa_inspect(...).columns` / `col_names`),
pas d'une liste figée par entité — donc toute nouvelle colonne du modèle est
automatiquement synchronisée."""
import pytest
from decimal import Decimal
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Sale import Sale
import api.services.local_sync_service as lss


class _FakeResponse:
    def __init__(self, data):
        self._data = data

    def json(self):
        return self._data


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


def test_push_serializes_change_due_and_loyalty_fields(db, tenant):
    """_serialize (push local→cloud) inclut les 3 champs sans configuration
    par champ — dérivés dynamiquement des colonnes du modèle Sale."""
    sale = Sale(
        tenant_id=tenant.id,
        reference="VNT-1",
        total_amount=Decimal("1000"),
        final_amount=Decimal("750"),
        paid_amount=Decimal("750"),
        change_due=Decimal("250"),
        loyalty_earned=Decimal("15"),
        loyalty_redeemed=Decimal("5"),
    )
    db.add(sale)
    db.flush()

    payload = lss._serialize([sale], lss._EXCLUDE_PUSH)
    assert len(payload) == 1
    assert float(payload[0]["change_due"]) == 250.0
    assert float(payload[0]["loyalty_earned"]) == 15.0
    assert float(payload[0]["loyalty_redeemed"]) == 5.0


def test_pull_applies_change_due_and_loyalty_fields_to_new_local_sale(db, tenant, monkeypatch):
    """Un enregistrement 'sale' venant du cloud, avec change_due/loyalty
    renseignés, doit créer une vente locale portant ces mêmes valeurs."""
    cloud_record = {
        "id": "8f1e2b2a-1111-4a11-9a11-000000000001",
        "tenant_id": tenant.id,
        "customer_id": None,
        "user_id": None,
        "warehouse_id": None,
        "reference": "VNT-CLOUD-1",
        "total_amount": 1000,
        "discount": 0,
        "discount_id": None,
        "final_amount": 750,
        "paid_amount": 750,
        "change_due": 250,
        "loyalty_earned": 15,
        "loyalty_redeemed": 5,
        "status": "PAID",
        "created_at": "2026-07-31T10:00:00",
        "updated_at": "2026-07-31T10:00:00",
    }

    monkeypatch.setattr(lss, "SYNC_ENTITIES", [
        {"type": "sale", "model": Sale, "direction": "both"},
    ])
    monkeypatch.setattr(lss, "_load_sync_credentials", lambda: ("https://cloud.example", "fake-token", True))

    def fake_http_post(url, json, headers, timeout=30):
        assert url.endswith("/api/sync/pull-batch")
        return _FakeResponse({"results": {
            "sale": {"records": [cloud_record], "has_more": False, "next_since": None},
        }})

    monkeypatch.setattr(lss, "_http_post", fake_http_post)

    result = lss.run_sync(db)
    assert result["ok"] is not False, result

    local_sale = db.query(Sale).filter(Sale.id == cloud_record["id"]).first()
    assert local_sale is not None
    assert float(local_sale.change_due) == 250.0
    assert float(local_sale.loyalty_earned) == 15.0
    assert float(local_sale.loyalty_redeemed) == 5.0
