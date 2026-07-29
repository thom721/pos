"""Bug corrigé : _sync_schema_from_models() ne générait une clause DEFAULT
que depuis Column.server_default — un default= Python (ex:
PlatformConfig.annual_discount_pct, default=20) n'était jamais honoré quand
la colonne était ajoutée après coup à une table déjà existante (ADD COLUMN),
retombant sur le neutre "DEFAULT 0" pour un entier NOT NULL. platform_config
étant une ligne unique, ce 0 s'affichait partout comme "Annuel -0%" au lieu
de -20%.
"""
import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.PlatformConfig import PlatformConfig
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


def test_add_column_honors_python_side_default(db):
    """Simule une table platform_config existante à laquelle il manque la
    colonne annual_discount_pct (comme en production avant ce correctif),
    et vérifie que _sync_schema_from_models() l'ajoute avec le bon DEFAULT
    DB-level (20, pas 0) — inspecté directement via PRAGMA table_info,
    plutôt qu'un INSERT brut qui échouerait sur d'autres colonnes NOT NULL
    dont le default= Python n'a jamais été un vrai DEFAULT SQL non plus
    (comportement normal, hors sujet de ce correctif)."""
    engine = db.info["engine"]

    with engine.connect() as conn:
        conn.execute(text("ALTER TABLE platform_config DROP COLUMN annual_discount_pct"))
        conn.commit()

    m._sync_schema_from_models(active_engine=engine)

    with engine.connect() as conn:
        cols = conn.execute(text("PRAGMA table_info(platform_config)")).fetchall()

    col_info = next(c for c in cols if c[1] == "annual_discount_pct")
    dflt_value = col_info[4]  # colonne 'dflt_value' de PRAGMA table_info
    assert dflt_value == "20"


def test_repair_fixes_existing_zero_value(db):
    engine = db.info["engine"]
    cfg = PlatformConfig(annual_discount_pct=0)
    db.add(cfg)
    db.commit()

    m._repair_annual_discount_default(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    reloaded = fresh.query(PlatformConfig).filter_by(id=cfg.id).first()
    assert reloaded.annual_discount_pct == 20


def test_repair_leaves_explicitly_configured_value_untouched(db):
    engine = db.info["engine"]
    cfg = PlatformConfig(annual_discount_pct=15)
    db.add(cfg)
    db.commit()

    m._repair_annual_discount_default(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    reloaded = fresh.query(PlatformConfig).filter_by(id=cfg.id).first()
    assert reloaded.annual_discount_pct == 15


def test_repair_is_idempotent(db):
    engine = db.info["engine"]
    cfg = PlatformConfig(annual_discount_pct=0)
    db.add(cfg)
    db.commit()

    m._repair_annual_discount_default(active_engine=engine)
    m._repair_annual_discount_default(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    reloaded = fresh.query(PlatformConfig).filter_by(id=cfg.id).first()
    assert reloaded.annual_discount_pct == 20
