"""cloud_login() choisit une caisse libre pour un nouvel appareil — deux bugs
corrigés ici :
1. Aucun respect du dépôt auquel l'utilisateur est rattaché (user.warehouse_id)
   — un utilisateur restreint pouvait atterrir sur une caisse d'un AUTRE dépôt.
2. Aucune priorité à une caisse encore utilisable (trial/abonnement actif) —
   le tri par last_seen (jamais utilisée d'abord) pouvait faire atterrir un
   nouvel appareil sur une caisse SANS plan alors qu'une autre, dans le même
   dépôt, avait un abonnement/essai encore valide."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.services.auth import get_password_hash
from api.services.tenant_service import cloud_login


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


def _make_user(db, tenant, *, warehouse_id=None, suffix=""):
    user = User(
        fname="U", lname="Test", username=f"user{suffix}",
        email=f"user{suffix}@t.com",
        password=get_password_hash("secret123"),
        tenant_id=tenant.id, roles=["cashier"], permissions=[], is_active=True,
        warehouse_id=[warehouse_id] if warehouse_id else None,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def test_login_prefers_register_in_users_assigned_warehouse(db, tenant):
    wh_a = Warehouse(tenant_id=tenant.id, name="Dépôt A", is_active=True, is_default=True)
    wh_b = Warehouse(tenant_id=tenant.id, name="Dépôt B", is_active=True)
    db.add_all([wh_a, wh_b])
    db.flush()

    reg_a = PosRegister(tenant_id=tenant.id, warehouse_id=wh_a.id, name="Caisse A", is_active=True)
    reg_b = PosRegister(tenant_id=tenant.id, warehouse_id=wh_b.id, name="Caisse B", is_active=True)
    db.add_all([reg_a, reg_b])
    db.commit()

    user = _make_user(db, tenant, warehouse_id=wh_b.id)

    result = cloud_login(db, user.email, "secret123", "dev-1", None)

    assert result["register_id"] == reg_b.id


def test_login_does_not_fall_back_outside_users_assigned_warehouse(db, tenant):
    """Un utilisateur restreint à un dépôt ne doit JAMAIS se retrouver lié à
    une caisse d'un autre dépôt — s'il n'y a aucune caisse libre dans le
    sien, register_id reste None (la connexion elle-même reste autorisée)."""
    wh_a = Warehouse(tenant_id=tenant.id, name="Dépôt A", is_active=True, is_default=True)
    wh_b = Warehouse(tenant_id=tenant.id, name="Dépôt B", is_active=True)
    db.add_all([wh_a, wh_b])
    db.flush()

    # Aucune caisse dans le dépôt B — l'utilisateur y est pourtant rattaché.
    reg_a = PosRegister(tenant_id=tenant.id, warehouse_id=wh_a.id, name="Caisse A", is_active=True)
    db.add(reg_a)
    db.commit()

    user = _make_user(db, tenant, warehouse_id=wh_b.id)

    result = cloud_login(db, user.email, "secret123", "dev-1", None)

    assert result["register_id"] is None


def test_login_prefers_register_with_active_plan_over_never_used_one(db, tenant):
    """Reproduit le bug rapporté : deux caisses dans le même dépôt, l'une
    avec un abonnement actif (déjà utilisée, last_seen posé), l'autre jamais
    utilisée et sans aucun plan (last_seen NULL, gagnait avant ce correctif
    car le tri ne considérait QUE last_seen)."""
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()

    reg_no_plan = PosRegister(
        tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse sans plan",
        is_active=True,
    )
    reg_active = PosRegister(
        tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse active",
        is_active=True,
        subscription_ends_at=now_local() + timedelta(days=10),
    )
    reg_active.last_seen = now_local() - timedelta(days=1)
    db.add_all([reg_no_plan, reg_active])
    db.commit()

    user = _make_user(db, tenant)

    result = cloud_login(db, user.email, "secret123", "dev-1", None)

    assert result["register_id"] == reg_active.id


def test_login_never_moves_device_off_its_own_register(db, tenant):
    """Reproduit le bug rapporté en prod : un appareil déjà lié à Caisse 2
    (sans plan) se reconnecte alors que Caisse 2 n'a PAS de session ouverte
    en ce moment — il ne doit JAMAIS être ré-attribué à Caisse One (avec un
    plan actif, libre) juste parce qu'elle est "meilleure". Un appareil
    garde toujours sa propre caisse tant qu'elle reste active."""
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()

    caisse_2 = PosRegister(
        tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse 2",
        is_active=True, device_id="dev-caisse-2", is_device_approved=True,
    )
    caisse_one = PosRegister(
        tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse One",
        is_active=True, subscription_ends_at=now_local() + timedelta(days=19),
    )
    db.add_all([caisse_2, caisse_one])
    db.commit()

    user = _make_user(db, tenant)

    # Caisse One vient de libérer sa session (n'a plus de session ouverte,
    # comme après une fermeture forcée) — l'appareil de Caisse 2 se reconnecte.
    result = cloud_login(db, user.email, "secret123", "dev-caisse-2", None)

    assert result["register_id"] == caisse_2.id
    db.refresh(caisse_2)
    # Toujours approuvé — jamais "rebindé", donc jamais révoqué.
    assert caisse_2.is_device_approved is True
    assert caisse_2.device_id == "dev-caisse-2"
    db.refresh(caisse_one)
    assert caisse_one.device_id is None


def test_login_never_steals_another_devices_register(db, tenant):
    """Reproduit le trou signalé : une caisse déjà liée à un AUTRE appareil
    (approuvé, juste sans session ouverte en ce moment — ex: fin de service)
    ne doit JAMAIS être considérée "libre" pour un nouvel appareil, même si
    elle a un abonnement actif et serait autrement la "meilleure" candidate.
    Un nouvel appareil doit atterrir sur une caisse vraiment jamais réclamée
    (device_id NULL), pas voler celle d'un collègue."""
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()

    # Caisse d'un collègue : approuvée, abonnement actif, mais sans session
    # ouverte en ce moment (il a fermé sa caisse pour une pause).
    caisse_collegue = PosRegister(
        tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse Collègue",
        is_active=True, device_id="dev-collegue", is_device_approved=True,
        subscription_ends_at=now_local() + timedelta(days=10),
    )
    # Caisse vraiment jamais réclamée, sans plan.
    caisse_libre = PosRegister(
        tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse Libre",
        is_active=True,
    )
    db.add_all([caisse_collegue, caisse_libre])
    db.commit()

    user = _make_user(db, tenant)

    result = cloud_login(db, user.email, "secret123", "dev-nouveau", None)

    assert result["register_id"] == caisse_libre.id
    db.refresh(caisse_collegue)
    assert caisse_collegue.device_id == "dev-collegue"
    assert caisse_collegue.is_device_approved is True


def test_login_returns_no_register_when_only_claimed_ones_exist(db, tenant):
    """Si la SEULE caisse existante appartient déjà à un autre appareil
    (sans session ouverte), un nouvel appareil ne doit ni la voler ni faire
    échouer la connexion — register_id reste None."""
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    caisse_collegue = PosRegister(
        tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse Collègue",
        is_active=True, device_id="dev-collegue", is_device_approved=True,
    )
    db.add(caisse_collegue)
    db.commit()

    user = _make_user(db, tenant)

    result = cloud_login(db, user.email, "secret123", "dev-nouveau", None)

    assert result["register_id"] is None
    db.refresh(caisse_collegue)
    assert caisse_collegue.device_id == "dev-collegue"


def test_login_falls_back_to_unusable_register_when_none_are_active(db, tenant):
    """Si AUCUNE caisse libre n'a de plan actif, le login ne doit pas
    échouer — il prend quand même un slot (comportement historique
    préservé : le login n'est jamais bloqué par la facturation)."""
    wh = Warehouse(tenant_id=tenant.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    reg = PosRegister(tenant_id=tenant.id, warehouse_id=wh.id, name="Caisse", is_active=True)
    db.add(reg)
    db.commit()

    user = _make_user(db, tenant)

    result = cloud_login(db, user.email, "secret123", "dev-1", None)

    assert result["register_id"] == reg.id
