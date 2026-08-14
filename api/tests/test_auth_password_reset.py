"""Réinitialisation de mot de passe depuis la page de connexion : demande
d'un code par email (forgot-password), puis vérification du code +
nouveau mot de passe (reset-password). Réponse toujours générique côté
forgot-password pour ne jamais révéler si un email existe."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.User import User
from api.services.auth import get_password_hash
from api.routes.auth import (
    ForgotPasswordRequest, ResetPasswordRequest, forgot_password, reset_password,
    _GENERIC_FORGOT_MESSAGE,
)


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def user(db):
    tenant = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(tenant)
    db.flush()
    u = User(
        tenant_id=tenant.id, fname="A", lname="B", username="ab",
        email="user@example.com", password=get_password_hash("OldPass123"),
        roles=["admin"], is_active=True,
    )
    db.add(u)
    db.commit()
    return u


def test_forgot_password_generates_code_for_existing_user(db, user):
    result = forgot_password(ForgotPasswordRequest(email="user@example.com"), db)

    assert result == {"message": _GENERIC_FORGOT_MESSAGE}
    db.refresh(user)
    assert user.password_reset_code is not None
    assert len(user.password_reset_code) == 6
    assert user.password_reset_expires_at is not None


def test_forgot_password_generic_message_for_unknown_email(db):
    result = forgot_password(ForgotPasswordRequest(email="ghost@nowhere.com"), db)
    assert result == {"message": _GENERIC_FORGOT_MESSAGE}


def test_forgot_password_email_case_insensitive(db, user):
    forgot_password(ForgotPasswordRequest(email="USER@EXAMPLE.COM"), db)
    db.refresh(user)
    assert user.password_reset_code is not None


def test_reset_password_with_valid_code_succeeds(db, user):
    forgot_password(ForgotPasswordRequest(email="user@example.com"), db)
    db.refresh(user)
    code = user.password_reset_code

    result = reset_password(
        ResetPasswordRequest(email="user@example.com", code=code, new_password="NewPass456"),
        db,
    )

    assert result["message"]
    db.refresh(user)
    assert user.password_reset_code is None
    assert user.password_reset_expires_at is None
    assert user.must_change_password is False
    assert user.offline_hash is not None
    # L'ancien mot de passe ne doit plus fonctionner, le nouveau doit être hashé (pas en clair)
    assert user.password != "NewPass456"


def test_reset_password_rejects_wrong_code(db, user):
    forgot_password(ForgotPasswordRequest(email="user@example.com"), db)
    from fastapi import HTTPException
    with pytest.raises(HTTPException) as exc:
        reset_password(
            ResetPasswordRequest(email="user@example.com", code="000000", new_password="NewPass456"),
            db,
        )
    assert exc.value.status_code == 400


def test_reset_password_rejects_expired_code(db, user):
    forgot_password(ForgotPasswordRequest(email="user@example.com"), db)
    db.refresh(user)
    user.password_reset_expires_at = now_local() - timedelta(minutes=1)
    db.commit()

    from fastapi import HTTPException
    with pytest.raises(HTTPException) as exc:
        reset_password(
            ResetPasswordRequest(
                email="user@example.com", code=user.password_reset_code, new_password="NewPass456",
            ),
            db,
        )
    assert exc.value.status_code == 400


def test_reset_password_rejects_short_password(db, user):
    forgot_password(ForgotPasswordRequest(email="user@example.com"), db)
    db.refresh(user)

    from fastapi import HTTPException
    with pytest.raises(HTTPException) as exc:
        reset_password(
            ResetPasswordRequest(email="user@example.com", code=user.password_reset_code, new_password="abc"),
            db,
        )
    assert exc.value.status_code == 400


def test_reset_password_without_prior_request_rejected(db, user):
    from fastapi import HTTPException
    with pytest.raises(HTTPException) as exc:
        reset_password(
            ResetPasswordRequest(email="user@example.com", code="123456", new_password="NewPass456"),
            db,
        )
    assert exc.value.status_code == 400
