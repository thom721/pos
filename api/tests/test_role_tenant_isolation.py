"""Isolation multi-tenant des rôles (api/routes/roles.py, api/core/permissions.py).

Bug corrigé : Role.name portait une contrainte UNIQUE globale — une seule
ligne "manager"/"cashier"/etc. existait pour TOUS les tenants de la
plateforme, donc un tenant modifiant les permissions d'un rôle intégré
changeait ce rôle pour tous les autres tenants aussi. Corrigé via
UniqueConstraint(tenant_id, name) + fork-on-write : modifier un rôle intégré
crée une copie propre au tenant (TENANT_ROLE_OVERRIDES / Role.tenant_id
renseigné) sans jamais toucher le défaut plateforme (Role.tenant_id NULL,
ROLE_PERMISSIONS)."""
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Role import Role
from api.models.Tenant import Tenant
from api.models.User import User
from api.core.permissions import ROLE_PERMISSIONS, TENANT_ROLE_OVERRIDES, has_permission
from api.routes import roles as roles_routes
from api.routes.roles import RoleCreate, RoleUpdate


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture(autouse=True)
def _clean_caches():
    """ROLE_PERMISSIONS/TENANT_ROLE_OVERRIDES sont des dicts globaux — isoler
    chaque test pour ne pas polluer les suivants."""
    saved_global = dict(ROLE_PERMISSIONS)
    saved_overrides = dict(TENANT_ROLE_OVERRIDES)
    TENANT_ROLE_OVERRIDES.clear()
    yield
    ROLE_PERMISSIONS.clear()
    ROLE_PERMISSIONS.update(saved_global)
    TENANT_ROLE_OVERRIDES.clear()
    TENANT_ROLE_OVERRIDES.update(saved_overrides)


@pytest.fixture()
def tenant_a(db):
    t = Tenant(business_name="A", owner_email="a@a.com", slug="a")
    db.add(t)
    db.flush()
    return t


@pytest.fixture()
def tenant_b(db):
    t = Tenant(business_name="B", owner_email="b@b.com", slug="b")
    db.add(t)
    db.flush()
    return t


@pytest.fixture()
def global_manager_role(db):
    """Simule le seed _BUILTIN_ROLES (api/main.py) — ligne globale tenant_id NULL."""
    r = Role(tenant_id=None, name="manager", label="Gérant", color="#0284C7",
             is_builtin=True, permissions=["sales.read", "connect.cloud"])
    db.add(r)
    db.commit()
    return r


def _user(db, tenant, role="admin"):
    u = User(tenant_id=tenant.id, fname="U", lname="T", username=f"u{tenant.id[:8]}",
             password="x", roles=[role], permissions=["all"], is_active=True)
    db.add(u)
    db.commit()
    return u


# ── has_permission tenant-aware ──────────────────────────────────────────────

def test_tenant_override_takes_precedence_over_global_default():
    ROLE_PERMISSIONS["manager"] = {"sales.read", "connect.cloud"}
    TENANT_ROLE_OVERRIDES[("tenant-a", "manager")] = {"sales.read"}  # connect.cloud retiré

    assert has_permission([], ["manager"], "connect.cloud", tenant_id="tenant-a") is False
    assert has_permission([], ["manager"], "sales.read", tenant_id="tenant-a") is True


def test_other_tenant_unaffected_by_override():
    ROLE_PERMISSIONS["manager"] = {"sales.read", "connect.cloud"}
    TENANT_ROLE_OVERRIDES[("tenant-a", "manager")] = {"sales.read"}

    # tenant-b n'a pas de surcharge — retombe sur le défaut plateforme intact
    assert has_permission([], ["manager"], "connect.cloud", tenant_id="tenant-b") is True


def test_no_tenant_id_uses_global_default_only():
    ROLE_PERMISSIONS["manager"] = {"sales.read", "connect.cloud"}
    TENANT_ROLE_OVERRIDES[("tenant-a", "manager")] = {"sales.read"}

    assert has_permission([], ["manager"], "connect.cloud", tenant_id=None) is True


# ── update_role : fork-on-write ──────────────────────────────────────────────

def test_update_builtin_role_forks_without_touching_global_row(db, tenant_a, tenant_b, global_manager_role):
    user_a = _user(db, tenant_a)

    result = roles_routes.update_role(
        "manager", RoleUpdate(permissions=["sales.read"]),
        db=db, current_user=user_a,
    )
    assert result["permissions"] == ["sales.read"]

    # Ligne globale intacte
    db.refresh(global_manager_role)
    assert set(global_manager_role.permissions) == {"sales.read", "connect.cloud"}

    # Une ligne distincte a été créée pour tenant_a
    fork = db.query(Role).filter(Role.tenant_id == tenant_a.id, Role.name == "manager").first()
    assert fork is not None
    assert fork.permissions == ["sales.read"]

    # tenant_b ne voit toujours que le défaut global
    user_b = _user(db, tenant_b)
    listed_b = roles_routes.list_roles(db=db, current_user=user_b)
    manager_b = next(r for r in listed_b if r["name"] == "manager")
    assert set(manager_b["permissions"]) == {"sales.read", "connect.cloud"}


def test_update_builtin_role_twice_updates_same_fork_not_duplicate(db, tenant_a, global_manager_role):
    user_a = _user(db, tenant_a)
    roles_routes.update_role("manager", RoleUpdate(permissions=["sales.read"]), db=db, current_user=user_a)
    roles_routes.update_role("manager", RoleUpdate(permissions=["stock.read"]), db=db, current_user=user_a)

    forks = db.query(Role).filter(Role.tenant_id == tenant_a.id, Role.name == "manager").all()
    assert len(forks) == 1
    assert forks[0].permissions == ["stock.read"]


def test_update_builtin_role_label_still_blocked_on_fork(db, tenant_a, global_manager_role):
    user_a = _user(db, tenant_a)
    with pytest.raises(HTTPException) as exc:
        roles_routes.update_role("manager", RoleUpdate(label="Nouveau nom"), db=db, current_user=user_a)
    assert exc.value.status_code == 403


def test_admin_role_never_modifiable(db, tenant_a):
    user_a = _user(db, tenant_a)
    with pytest.raises(HTTPException) as exc:
        roles_routes.update_role("admin", RoleUpdate(permissions=["all"]), db=db, current_user=user_a)
    assert exc.value.status_code == 403


# ── create_role : isolation des rôles personnalisés ──────────────────────────

def test_two_tenants_can_create_custom_role_with_same_name(db, tenant_a, tenant_b):
    user_a = _user(db, tenant_a)
    user_b = _user(db, tenant_b)

    role_a = roles_routes.create_role(
        RoleCreate(name="superviseur", label="Superviseur", permissions=["sales.read"]),
        db=db, current_user=user_a,
    )
    role_b = roles_routes.create_role(
        RoleCreate(name="superviseur", label="Superviseur B", permissions=["stock.read"]),
        db=db, current_user=user_b,
    )
    assert role_a["permissions"] == ["sales.read"]
    assert role_b["permissions"] == ["stock.read"]

    rows = db.query(Role).filter(Role.name == "superviseur").all()
    assert len(rows) == 2
    assert {r.tenant_id for r in rows} == {tenant_a.id, tenant_b.id}


def test_create_role_rejects_reserved_admin_name(db, tenant_a):
    user_a = _user(db, tenant_a)
    with pytest.raises(HTTPException) as exc:
        roles_routes.create_role(
            RoleCreate(name="admin", label="Faux admin", permissions=["all"]),
            db=db, current_user=user_a,
        )
    assert exc.value.status_code == 400


def test_create_role_rejects_builtin_name(db, tenant_a, global_manager_role):
    user_a = _user(db, tenant_a)
    with pytest.raises(HTTPException) as exc:
        roles_routes.create_role(
            RoleCreate(name="manager", label="Autre gérant", permissions=[]),
            db=db, current_user=user_a,
        )
    assert exc.value.status_code == 400


def test_custom_role_not_visible_to_other_tenant(db, tenant_a, tenant_b):
    user_a = _user(db, tenant_a)
    user_b = _user(db, tenant_b)
    roles_routes.create_role(
        RoleCreate(name="superviseur", label="Superviseur", permissions=["sales.read"]),
        db=db, current_user=user_a,
    )
    listed_b = roles_routes.list_roles(db=db, current_user=user_b)
    assert all(r["name"] != "superviseur" for r in listed_b)


# ── delete_role : reset au défaut plateforme, jamais cross-tenant ────────────

def test_delete_fork_resets_to_global_default(db, tenant_a, global_manager_role):
    user_a = _user(db, tenant_a)
    roles_routes.update_role("manager", RoleUpdate(permissions=["sales.read"]), db=db, current_user=user_a)

    roles_routes.delete_role("manager", db=db, current_user=user_a)

    fork = db.query(Role).filter(Role.tenant_id == tenant_a.id, Role.name == "manager").first()
    assert fork is None
    listed = roles_routes.list_roles(db=db, current_user=user_a)
    manager = next(r for r in listed if r["name"] == "manager")
    assert set(manager["permissions"]) == {"sales.read", "connect.cloud"}  # défaut global


def test_delete_global_builtin_role_blocked(db, tenant_a, global_manager_role):
    user_a = _user(db, tenant_a)
    with pytest.raises(HTTPException) as exc:
        roles_routes.delete_role("manager", db=db, current_user=user_a)
    assert exc.value.status_code == 404  # tenant_a n'a pas de fork, rien à "eux" à supprimer


def test_delete_other_tenant_custom_role_returns_404(db, tenant_a, tenant_b):
    user_a = _user(db, tenant_a)
    user_b = _user(db, tenant_b)
    roles_routes.create_role(
        RoleCreate(name="superviseur", label="Superviseur", permissions=[]),
        db=db, current_user=user_a,
    )
    with pytest.raises(HTTPException) as exc:
        roles_routes.delete_role("superviseur", db=db, current_user=user_b)
    assert exc.value.status_code == 404


# ── _expand_permissions (tenant_service.py) — utilisé à cloud_login ──────────

def test_expand_permissions_uses_own_tenant_fork_not_another_tenants(db, tenant_a, tenant_b, global_manager_role):
    from api.services.tenant_service import _expand_permissions

    user_a = _user(db, tenant_a, role="manager")
    user_a.permissions = []
    db.commit()

    # tenant_b forke "manager" avec un jeu de permissions différent
    user_b_admin = _user(db, tenant_b)
    roles_routes.update_role("manager", RoleUpdate(permissions=["stock.read"]), db=db, current_user=user_b_admin)

    # user_a (tenant_a) doit retomber sur le défaut global, pas le fork de tenant_b
    perms = _expand_permissions(user_a, db)
    assert set(perms) == {"sales.read", "connect.cloud"}
    assert "stock.read" not in perms


# ── Nouveau tenant : aucun seed de rôle propre nécessaire ────────────────────

def test_fresh_tenant_gets_correct_defaults_via_global_seed_only(db, tenant_a, global_manager_role):
    """register_tenant (tenant_service.py) ne crée jamais de ligne Role pour
    le nouveau tenant — seul le seed GLOBAL des rôles intégrés (fait une
    fois pour toute la plateforme au démarrage de main.py, indépendamment de
    la création d'un tenant précis) doit exister pour qu'un tenant tout
    juste créé résolve correctement manager/cashier via le fallback."""
    from api.services.tenant_service import _expand_permissions

    # Aucune ligne Role propre à tenant_a — seule la ligne globale existe
    # (fixture global_manager_role, qui simule le seed _BUILTIN_ROLES réel)
    assert db.query(Role).filter(Role.tenant_id == tenant_a.id).count() == 0

    user = _user(db, tenant_a, role="manager")
    user.permissions = []
    db.commit()

    perms = _expand_permissions(user, db)
    assert set(perms) == {"sales.read", "connect.cloud"}


# ── resolve_effective_permissions — /login, /register, GET /users/me ────────

def test_resolve_effective_permissions_uses_tenant_fork():
    from api.core.permissions import resolve_effective_permissions

    ROLE_PERMISSIONS["manager"] = {"sales.read", "connect.cloud"}
    TENANT_ROLE_OVERRIDES[("tenant-a", "manager")] = {"sales.read"}  # connect.cloud retiré

    perms = resolve_effective_permissions(["manager"], [], tenant_id="tenant-a")
    assert perms == ["sales.read"]


def test_resolve_effective_permissions_other_tenant_uses_global_default():
    from api.core.permissions import resolve_effective_permissions

    ROLE_PERMISSIONS["manager"] = {"sales.read", "connect.cloud"}
    TENANT_ROLE_OVERRIDES[("tenant-a", "manager")] = {"sales.read"}

    perms = resolve_effective_permissions(["manager"], [], tenant_id="tenant-b")
    assert set(perms) == {"sales.read", "connect.cloud"}


def test_auth_and_user_routes_delegate_to_shared_resolver(db, tenant_a, global_manager_role):
    """routes/auth.py (/login) et routes/user.py (GET /users/me) avaient
    chacun leur propre copie de ce calcul, sans tenir compte du tenant —
    vérifie qu'ils délèguent maintenant tous les deux à la même fonction
    tenant-aware plutôt que de réintroduire une divergence."""
    from api.routes.auth import _resolve_permissions as auth_resolve
    from api.routes.user import _resolve_permissions as user_resolve

    user_a = _user(db, tenant_a, role="manager")
    user_a.permissions = []
    db.commit()

    roles_routes.update_role("manager", RoleUpdate(permissions=["sales.read"]), db=db, current_user=user_a)
    _reload_permissions_cache(db)

    assert auth_resolve(user_a) == ["sales.read"]
    assert user_resolve(user_a) == ["sales.read"]


def _reload_permissions_cache(db):
    from api.routes.roles import _reload_permissions
    _reload_permissions(db)
