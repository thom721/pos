"""Bug corrigé : _sync_schema_from_models() ajoute les colonnes manquantes
via ALTER TABLE ... DEFAULT, qui ne touche jamais updated_at des lignes déjà
présentes. Sur une installation locale (serveur frozen, Alembic ignoré),
le curseur de synchro (SyncState.last_pull_at) est basé sur updated_at côté
cloud — sans réinitialisation, ces lignes déjà synchronisées avant l'ajout
de la colonne ne sont donc plus jamais re-tirées, et la valeur par défaut
locale (ex: Product.is_service=False) reste figée pour toujours, même après
mise à jour du serveur local. Constaté en prod sur des produits service
synchronisés avant l'ajout de is_service au modèle.
"""
import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.SyncState import SyncState
import api.main as m


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    session.info["engine"] = engine
    yield session
    session.close()


def _set_watermark(db, entity_type: str, value) -> None:
    db.add(SyncState(entity_type=entity_type, last_pull_at=value, last_push_at=value))
    db.commit()


def test_adding_a_column_resets_the_pull_watermark_for_its_entity(db):
    engine = db.info["engine"]
    from datetime import datetime
    stale_cursor = datetime(2026, 1, 1)

    _set_watermark(db, "product", stale_cursor)
    _set_watermark(db, "customer", stale_cursor)  # entité non affectée — témoin

    with engine.connect() as conn:
        conn.execute(text("ALTER TABLE products DROP COLUMN is_service"))
        conn.commit()

    m._sync_schema_from_models(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    product_state = fresh.query(SyncState).filter_by(entity_type="product").first()
    customer_state = fresh.query(SyncState).filter_by(entity_type="customer").first()

    assert product_state.last_pull_at is None, \
        "le curseur product doit être réinitialisé après l'ajout de is_service"
    assert customer_state.last_pull_at == stale_cursor, \
        "une entité dont la table n'a pas changé ne doit pas être affectée"


def test_no_missing_column_leaves_watermark_untouched(db):
    engine = db.info["engine"]
    from datetime import datetime
    cursor = datetime(2026, 1, 1)
    _set_watermark(db, "product", cursor)

    # Rien à ajouter cette fois — colonne déjà présente.
    m._sync_schema_from_models(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    product_state = fresh.query(SyncState).filter_by(entity_type="product").first()
    assert product_state.last_pull_at == cursor
