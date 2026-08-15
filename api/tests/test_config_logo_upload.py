"""Test HTTP de bout en bout pour POST /api/config/logo — bug rapporté :
"Erreur upload" générique côté web après avoir ajouté ?warehouse_id= à
l'appel (frontend/profile_screen.dart). Vérifie que l'endpoint accepte
bien un warehouse_id valide en query param en plus du fichier multipart.
"""
import io

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import api.models  # noqa: F401
from api.database import Base, get_db
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Warehouse import Warehouse
from api.core.security import create_access_token
import api.main as main_module


@pytest.fixture()
def engine():
    return create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )


@pytest.fixture()
def db(engine):
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def client(engine):
    TestSession = sessionmaker(bind=engine)

    def _override_get_db():
        db = TestSession()
        try:
            yield db
        finally:
            db.close()

    main_module.app.dependency_overrides[get_db] = _override_get_db
    with TestClient(main_module.app, raise_server_exceptions=True) as c:
        yield c
    main_module.app.dependency_overrides.clear()


@pytest.fixture()
def tenant_and_warehouse(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Dépôt principal", is_default=True)
    db.add(wh)
    db.flush()
    return t, wh


@pytest.fixture()
def admin_token(db, tenant_and_warehouse):
    t, _wh = tenant_and_warehouse
    user = User(
        fname="Admin", lname="Test", username="admin_test",
        email="admin_test@t.com", password="x", tenant_id=t.id,
        roles=["admin"], permissions=["all"], is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token({"sub": user.id, "perm_v": user.permissions_version or 0})
    return token


def _tiny_png_bytes() -> bytes:
    # 1x1 PNG minimal valide
    return bytes.fromhex(
        "89504e470d0a1a0a0000000d494844520000000100000001080600000"
        "01f15c4890000000a49444154789c6360000002000100ffff03000006"
        "0005574bda480000000049454e44ae426082"
    )


def test_upload_logo_with_warehouse_id_query_param_returns_200(
    client, admin_token, tenant_and_warehouse
):
    _t, wh = tenant_and_warehouse
    headers = {"Authorization": f"Bearer {admin_token}"}
    files = {"file": ("logo.png", io.BytesIO(_tiny_png_bytes()), "image/png")}

    res = client.post(
        f"/api/config/logo?warehouse_id={wh.id}", files=files, headers=headers
    )

    assert res.status_code == 200, res.text
    assert res.json()["logo_path"].startswith("/static/logos/")


def test_upload_logo_without_warehouse_id_still_returns_200(client, admin_token):
    headers = {"Authorization": f"Bearer {admin_token}"}
    files = {"file": ("logo.png", io.BytesIO(_tiny_png_bytes()), "image/png")}

    res = client.post("/api/config/logo", files=files, headers=headers)

    assert res.status_code == 200, res.text


def test_logo_uploaded_without_warehouse_reflects_on_a_different_warehouse(
    client, admin_token, db, tenant_and_warehouse
):
    """Bug réel : un logo uploadé depuis le web (sans warehouse_id, donc
    écrit sur la ligne globale) restait invisible pour une app bureau déjà
    liée à un dépôt précis, dont la ligne AppConfig avait été créée (copiée
    depuis la globale) AVANT cet upload — plus jamais resynchronisée.
    """
    t, _wh1 = tenant_and_warehouse
    wh2 = Warehouse(tenant_id=t.id, name="Autre dépôt", is_default=False)
    db.add(wh2)
    db.commit()
    db.refresh(wh2)
    headers = {"Authorization": f"Bearer {admin_token}"}

    # L'app bureau, liée au 2e dépôt, consulte sa config une première fois —
    # ça crée sa propre ligne AppConfig (copiée depuis la globale, vide).
    res = client.get(f"/api/config/?warehouse_id={wh2.id}", headers=headers)
    assert res.status_code == 200, res.text
    assert res.json()["logo_path"] == ""

    # Le web uploade un logo sans warehouse_id (écrit sur la ligne globale).
    files = {"file": ("logo.png", io.BytesIO(_tiny_png_bytes()), "image/png")}
    res = client.post("/api/config/logo", files=files, headers=headers)
    assert res.status_code == 200, res.text
    uploaded_path = res.json()["logo_path"]
    assert uploaded_path.startswith("/static/logos/")

    # L'app bureau (2e dépôt) revoit sa config : doit refléter le nouveau logo.
    res = client.get(f"/api/config/?warehouse_id={wh2.id}", headers=headers)
    assert res.status_code == 200, res.text
    assert res.json()["logo_path"] == uploaded_path
