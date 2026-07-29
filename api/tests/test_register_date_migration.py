"""Migration du chiffrement des dates de caisse vers la clé partagée.

Contexte : PosRegister.trial_ends_at / subscription_ends_at étaient chiffrées
avec une clé dérivée de settings.SECRET_KEY — propre à chaque serveur. Comme
pos_register se synchronise entre le cloud et les installations locales, un
serveur ne pouvait jamais déchiffrer une date chiffrée par un autre serveur.
"""
from datetime import datetime

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401 — enregistre tous les modèles auprès de Base.metadata
from api.database import Base
from api.models.Tenant import Tenant
from api.models.PosRegister import PosRegister
from api.core import billing_crypto as bc
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


@pytest.fixture()
def register(db):
    tenant = Tenant(business_name="Test", owner_email="t@test.com", slug="test-tenant")
    db.add(tenant)
    db.flush()
    reg = PosRegister(tenant_id=tenant.id, device_id="dev1", name="Caisse 1")
    db.add(reg)
    db.flush()
    return reg


def _encrypt_legacy(register_id: str, dt: datetime) -> str:
    """Chiffre une date avec l'ANCIEN schéma (clé = settings.SECRET_KEY)."""
    return bc._derive_register_fernet_legacy(register_id).encrypt(
        dt.isoformat().encode("utf-8")
    ).decode("utf-8")


def test_legacy_data_unreadable_before_migration(db, register):
    """Confirme le bug : une date chiffrée avec l'ancien schéma est illisible
    via la propriété normale (nouveau schéma) tant que la migration n'a pas
    tourné."""
    old_dt = datetime(2026, 8, 15, 12, 0, 0)
    register._trial_ends_at = _encrypt_legacy(register.id, old_dt)
    db.commit()
    db.refresh(register)

    assert register.trial_ends_at is None


def test_migration_recovers_legacy_dates(db, register):
    """La migration déchiffre avec l'ancien schéma et re-chiffre avec la
    clé fixe partagée — la date redevient lisible avec la valeur exacte."""
    engine = db.info["engine"]
    old_dt = datetime(2026, 8, 15, 12, 0, 0)
    register._trial_ends_at = _encrypt_legacy(register.id, old_dt)
    db.commit()

    m._migrate_register_dates_to_shared_key(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    reloaded = fresh.query(PosRegister).filter_by(id=register.id).first()
    assert reloaded.trial_ends_at == old_dt


def test_migration_is_idempotent(db, register):
    """Relancer la migration une deuxième fois ne modifie rien et ne casse
    pas les données déjà migrées."""
    engine = db.info["engine"]
    old_dt = datetime(2026, 8, 15, 12, 0, 0)
    register._trial_ends_at = _encrypt_legacy(register.id, old_dt)
    db.commit()

    m._migrate_register_dates_to_shared_key(active_engine=engine)
    m._migrate_register_dates_to_shared_key(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    reloaded = fresh.query(PosRegister).filter_by(id=register.id).first()
    assert reloaded.trial_ends_at == old_dt


def test_new_scheme_data_untouched_by_migration(db, register):
    """Une donnée déjà chiffrée avec le nouveau schéma (clé fixe) reste
    inchangée — la migration ne doit pas la modifier ni la casser."""
    engine = db.info["engine"]
    new_dt = datetime(2026, 9, 1, 8, 0, 0)
    register.trial_ends_at = new_dt  # passe par le setter → nouveau schéma
    db.commit()

    m._migrate_register_dates_to_shared_key(active_engine=engine)

    Session = sessionmaker(bind=engine)
    fresh = Session()
    reloaded = fresh.query(PosRegister).filter_by(id=register.id).first()
    assert reloaded.trial_ends_at == new_dt
