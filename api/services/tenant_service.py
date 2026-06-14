import re
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from api.models.Tenant import Tenant
from api.models.User import User
from api.models.AppConfig import AppConfig
from api.models.PosRegister import PosRegister
from api.models.PlatformConfig import PlatformConfig
from api.services.auth import Auth
from api.core.security import create_access_token


def _get_trial_days(db: Session) -> int:
    cfg = db.query(PlatformConfig).first()
    return int(cfg.trial_days) if cfg and cfg.trial_days else 30


def _slugify(name: str) -> str:
    slug = re.sub(r"[^\w\s-]", "", name.lower())
    slug = re.sub(r"[\s_-]+", "-", slug).strip("-")
    return slug[:60]


def _unique_slug(db: Session, base: str) -> str:
    slug = base
    i = 1
    while db.query(Tenant).filter(Tenant.slug == slug).first():
        slug = f"{base}-{i}"
        i += 1
    return slug


def register_tenant(db: Session, business_name: str, owner_email: str,
                    password: str, phone: str | None = None) -> tuple[Tenant, User]:
    """
    Creates a new Tenant + admin User.
    Called from the public /register endpoint and from payment webhooks.
    """
    if db.query(Tenant).filter(Tenant.owner_email == owner_email).first():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="Un compte existe déjà avec cet email")

    if db.query(User).filter(User.email == owner_email).first():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="Cet email est déjà utilisé")

    slug = _unique_slug(db, _slugify(business_name))
    trial_ends = datetime.now(timezone.utc) + timedelta(days=_get_trial_days(db))

    tenant = Tenant(
        slug=slug,
        business_name=business_name,
        owner_email=owner_email,
        phone=phone,
        status="trial",
        trial_ends_at=trial_ends,
    )
    db.add(tenant)
    db.flush()  # get tenant.id

    auth = Auth(db)
    username = slug  # unique because slug is unique
    user = User(
        tenant_id=tenant.id,
        fname=business_name,
        lname="",
        username=username,
        email=owner_email,
        phone=phone or "",
        password=auth.get_password_hash(password),
        roles=["admin"],
        permissions=[],
        must_change_password=False,
    )
    db.add(user)

    # Default AppConfig for this tenant
    config = AppConfig(tenant_id=tenant.id, business_name=business_name)
    db.add(config)

    db.commit()
    db.refresh(tenant)
    db.refresh(user)
    return tenant, user


def cloud_login(db: Session, email: str, password: str,
                device_id: str | None, register_name: str | None) -> dict:
    """
    Authenticates a cloud user by email, returns JWT + register info.
    Creates a new PosRegister if device_id is new for this tenant.
    """
    auth = Auth(db)
    user = auth.authenticate_by_email(email, password)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Email ou mot de passe incorrect")

    if not user.tenant_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Ce compte n'est pas associé à un tenant cloud")

    tenant = db.query(Tenant).filter(Tenant.id == user.tenant_id).first()
    if not tenant:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Tenant introuvable")

    if tenant.status == "suspended":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Abonnement suspendu — veuillez renouveler")

    if tenant.status == "trial" and tenant.trial_ends_at:
        trial_end = tenant.trial_ends_at
        if trial_end.tzinfo is None:
            trial_end = trial_end.replace(tzinfo=timezone.utc)
        if datetime.now(timezone.utc) > trial_end:
            tenant.status = "suspended"
            db.commit()
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="Période d'essai expirée — veuillez souscrire")

    # Register the device if device_id provided
    register_id = None
    if device_id:
        register = db.query(PosRegister).filter(
            PosRegister.tenant_id == tenant.id,
            PosRegister.device_id == device_id,
        ).first()
        if not register:
            register = PosRegister(
                tenant_id=tenant.id,
                device_id=device_id,
                name=register_name or f"Caisse {device_id[:8]}",
            )
            db.add(register)
            db.commit()
            db.refresh(register)
        register_id = register.id

    token_data = {
        "sub": user.username,
        "tenant_id": tenant.id,
        "tenant_status": tenant.status,
        "role": (user.roles or ["cashier"])[0],
        "device_id": device_id,
    }
    access_token = create_access_token(token_data)

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "tenant": tenant,
        "user": {
            "id": user.id,
            "username": user.username,
            "fname": user.fname,
            "lname": user.lname,
            "email": user.email,
            "roles": user.roles,
            "permissions": user.permissions,
            "must_change_password": user.must_change_password,
        },
        "register_id": register_id,
    }
