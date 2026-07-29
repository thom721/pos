"""Correctif : la sync (push local→cloud, pull cloud→local) construisait les
modèles SQLAlchemy à partir des dicts JSON bruts, où les colonnes Enum sont
représentées par leur `.value` (format API) — ex: StockType.in_ → "in".

Mais StockMovement.type n'a pas de values_callable : sa DDL utilise le NOM du
membre ("in_"), pas sa valeur ("in"). Assigner la string brute "in" au
constructeur du modèle contourne la conversion normale de SQLAlchemy et
provoque, sur MySQL (qui valide réellement les labels ENUM), l'erreur
`Data truncated for column 'type'` — reproduit en production lors d'une
installation fraîche (push d'un stock_movement type=IN vers le cloud).

coerce_enums() reconvertit la string brute en membre Enum Python avant
construction du modèle, laissant SQLAlchemy dériver le bon label au flush.
"""
from api.core.dt_coerce import coerce_enums
from api.models.StockMovement import StockMovement, StockType
from api.models.Sale import Sale, SaleStatus


def test_stock_movement_type_in_is_coerced_to_enum_member():
    # "in" est la .value du membre StockType.in_ (dont le .name est "in_",
    # utilisé comme label DB puisque cette colonne n'a pas de values_callable).
    record = {"id": "x", "type": "in", "quantity": 5}
    result = coerce_enums(StockMovement, record)
    assert result["type"] is StockType.in_
    assert result["quantity"] == 5  # colonnes non-enum inchangées


def test_stock_movement_type_out_and_adjust_also_coerced():
    assert coerce_enums(StockMovement, {"type": "out"})["type"] is StockType.out
    assert coerce_enums(StockMovement, {"type": "adjust"})["type"] is StockType.adjust


def test_sale_status_value_based_column_still_coerced_correctly():
    # Sale.status a values_callable=[e.value for e in obj] → label DB = "PAID".
    record = {"id": "x", "status": "PAID"}
    result = coerce_enums(Sale, record)
    assert result["status"] is SaleStatus.paid


def test_missing_key_and_non_string_values_untouched():
    record = {"quantity": 5, "note": None}
    result = coerce_enums(StockMovement, record)
    assert result == record


def test_invalid_enum_string_left_as_is_not_crashing():
    record = {"type": "not_a_real_type"}
    result = coerce_enums(StockMovement, record)
    assert result["type"] == "not_a_real_type"


def test_coerced_enum_produces_correct_bind_value_for_insert():
    """Vérifie que l'instance Enum reconvertie, une fois passée à SQLAlchemy,
    produit bien le label DB attendu (celui déjà présent en production) plutôt
    que la string brute reçue sur le fil."""
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    from api.database import Base
    from api.models.Tenant import Tenant
    import api.models  # noqa: F401

    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    db = Session()

    tenant = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(tenant)
    db.flush()

    record = {"id": "mv1", "type": "in", "quantity": 3, "tenant_id": tenant.id}
    coerced = coerce_enums(StockMovement, record)
    db.add(StockMovement(**coerced))
    db.commit()

    reloaded = db.get(StockMovement, "mv1")
    assert reloaded.type is StockType.in_
