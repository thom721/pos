import re
import uuid
from datetime import timedelta

from sqlalchemy import or_
from api.models.CashierSession import CashierSession
from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.AppConfig import AppConfig
from api.models.PosRegister import PosRegister
from api.models.Warehouse import Warehouse
from api.models.PlatformConfig import PlatformConfig
from api.models.Role import Role
from api.models.InstallationCode import InstallationCode, generate_installation_code
from api.services.auth import Auth
from api.core.security import create_access_token
from api.services.warehouse_helper import bind_register_device



def _expand_permissions(user: User, db: Session) -> list[str]:
    """Retourne la liste complète des permissions effectives d'un utilisateur.

    Fusionne les permissions individuelles (user.permissions) avec celles
    définies en DB pour chaque rôle de l'utilisateur.
    """
    individual = set(user.permissions or [])
    if "all" in individual:
        return ["all"]

    role_perms: set[str] = set()
    for role_name in (user.roles or []):
        if role_name == "admin":
            return ["all"]
        role = db.query(Role).filter(Role.name == role_name).first()
        if role and role.permissions:
            perms = role.permissions if isinstance(role.permissions, list) else []
            if "all" in perms:
                return ["all"]
            role_perms.update(perms)

    # Fusionner rôle + permissions individuelles supplémentaires
    merged = role_perms | (individual - set(user.roles or []))
    return list(merged)


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
    trial_ends = now_local() + timedelta(days=_get_trial_days(db))

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

    # Default warehouse + Caisse 1 slot included in every plan
    warehouse = Warehouse(
        tenant_id=tenant.id,
        name="Business Principale",
        is_active=True,
        is_default=True,
        is_claimed=False,   # non réclamé — le premier appareil le configure via code d'installation
    )
    db.add(warehouse)
    db.flush()  # get warehouse.id

    # Code d'installation pour le dépôt principal
    db.add(InstallationCode(
        code=generate_installation_code(),
        tenant_id=tenant.id,
        warehouse_id=warehouse.id,
    ))

    register = PosRegister(
        tenant_id=tenant.id,
        warehouse_id=warehouse.id,
        name="Caisse principale",
        is_active=True,
        is_initial=True,
        trial_ends_at=now_local() + timedelta(days=_get_trial_days(db)),
        # device_id intentionally NULL — claimed by first device to log in
    )
    db.add(register)

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

    # Pas de slot — une caisse est libre dès qu'elle n'a pas de session ouverte.
    register_id = None
    session_token = None
    if device_id:
        open_reg_ids = (
            db.query(CashierSession.register_id)
            .filter(CashierSession.status == "open")
            .scalar_subquery()
        )

        # 1. Ce device a déjà une caisse active → la garder, qu'une session y
        # soit ouverte ou non. Ne JAMAIS faire "flotter" un appareil déjà lié
        # vers une autre caisse simplement parce qu'elle a un abonnement actif
        # ou vient de se libérer (bug observé : fermer la session d'une caisse
        # payante ré-attribuait un appareil déjà approuvé d'une autre caisse
        # vers elle, révoquant son approbation au passage). Cohérent avec
        # _get_or_create_register (open_session), qui applique déjà cette
        # même règle sans exiger de session ouverte.
        register = db.query(PosRegister).filter(
            PosRegister.tenant_id == tenant.id,
            PosRegister.device_id == device_id,
            PosRegister.is_active == True,  # noqa: E712
        ).first()

        if not register:
            # 2. Prendre une caisse active sans session ouverte — restreinte
            # au(x) dépôt(s) auquel l'utilisateur est rattaché (user.warehouse_id ;
            # vide = accès à tous), SANS repli sur le reste du tenant : un
            # utilisateur restreint à un dépôt ne doit jamais se retrouver lié
            # à une caisse d'un autre dépôt. S'il n'y a aucune caisse libre
            # dans son/ses dépôt(s), register reste None — la connexion reste
            # autorisée (jamais bloquée par la limite de caisses), mais sans
            # caisse pré-assignée ; open_session s'en chargera plus tard
            # (et peut au besoin en créer une dans le bon dépôt).
            # Parmi les candidates, priorité à une caisse encore utilisable
            # (trial/abonnement actif) plutôt qu'une caisse bloquée, pour ne
            # pas atterrir sur un slot mort alors qu'un autre fonctionne.
            # device_id IS NULL : une caisse déjà liée à un AUTRE appareil ne
            # redevient jamais "libre" simplement parce qu'elle n'a pas de
            # session ouverte en ce moment (ex: fin de service) — sinon
            # n'importe quel login pourrait la voler à son propriétaire
            # légitime. Seule une réinitialisation admin (reset_device) la
            # remet vraiment à disposition.
            base_q = db.query(PosRegister).filter(
                PosRegister.tenant_id == tenant.id,
                PosRegister.is_active == True,   # noqa: E712
                PosRegister.id.not_in(open_reg_ids),
                PosRegister.device_id.is_(None),
            )
            user_warehouse_ids = user.warehouse_id or []
            candidates = (
                base_q.filter(PosRegister.warehouse_id.in_(user_warehouse_ids)).all()
                if user_warehouse_ids else base_q.all()
            )

            def _is_usable(r: PosRegister) -> bool:
                now = now_local()
                sub_ok   = r.subscription_ends_at is not None and r.subscription_ends_at > now
                trial_ok = r.trial_ends_at        is not None and r.trial_ends_at        > now
                return sub_ok or trial_ok

            candidates.sort(key=lambda r: (
                not _is_usable(r),
                r.last_seen is not None,
                r.last_seen or now_local(),
            ))
            register = candidates[0] if candidates else None

            if register:
                bind_register_device(register, device_id)

        if register:
            # Rotate session token and stamp last_seen on every login
            session_token = str(uuid.uuid4())
            register.session_token = session_token
            register.last_seen = now_local()
            db.commit()
            db.refresh(register)
            register_id = register.id

    # Avertissement plan expirant (≤ 5 jours avant la fin)
    from api.core.tenant import plan_warning, _check_tenant_access
    _check_tenant_access(tenant, db, hard_block=False)  # met à jour le statut
    warning = plan_warning(tenant)
    if warning and user.email == tenant.owner_email:
        from api.utils.email import maybe_send_warning
        maybe_send_warning(tenant, db)

    token_data = {
        "sub": user.username,
        "tenant_id": tenant.id,
        "tenant_status": tenant.status,
        "role": (user.roles or ["cashier"])[0],
        "device_id": device_id,
        "sid": session_token,   # session token — validated on each request
        "perm_v": user.permissions_version or 0,
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
            "permissions": _expand_permissions(user, db),
            "must_change_password": user.must_change_password,
            "warehouse_id": user.warehouse_id,
        },
        "register_id": register_id,
        "plan_warning": warning,
    }
