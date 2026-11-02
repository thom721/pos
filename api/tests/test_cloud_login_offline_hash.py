"""cloud_login() doit renseigner user.offline_hash s'il est vide — sinon un
tenant purement cloud (jamais de serveur local, jamais de /api/auth/login)
ne le renseigne JAMAIS, et GET /api/users/offline-sync ne peut alors mettre
aucun utilisateur en cache pour l'auth hors ligne sur les terminaux "client
cloud direct" (voir api/routes/user.py::list_users_offline_sync)."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.User import User
from api.services.auth import get_password_hash
from api.services.tenant_service import cloud_login
from api.services.user_service import compute_offline_hash


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


def _make_user(db, tenant, *, offline_hash=None):
    user = User(
        fname="U", lname="Test", username="user1", email="user1@t.com",
        password=get_password_hash("secret123"),
        tenant_id=tenant.id, roles=["cashier"], permissions=[], is_active=True,
        offline_hash=offline_hash,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def test_cloud_login_sets_offline_hash_when_missing(db, tenant):
    user = _make_user(db, tenant, offline_hash=None)

    cloud_login(db, email="user1@t.com", password="secret123",
                 device_id=None, register_name=None)

    db.refresh(user)
    assert user.offline_hash == compute_offline_hash("user1@t.com", "secret123")


def test_cloud_login_does_not_overwrite_existing_offline_hash(db, tenant):
    user = _make_user(db, tenant, offline_hash="deja-present")

    cloud_login(db, email="user1@t.com", password="secret123",
                 device_id=None, register_name=None)

    db.refresh(user)
    assert user.offline_hash == "deja-present"
