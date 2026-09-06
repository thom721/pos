from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional

from api.database import get_db
from api.dependencies.auth import require_permission
from api.models.User import User
from api.models.Role import Role
from api.core.permissions import P, ROLE_PERMISSIONS, TENANT_ROLE_OVERRIDES, load_roles_from_db

router = APIRouter(prefix="/api/roles", tags=["Roles"])

# ── Schemas ──────────────────────────────────────────────────────────────────

class RoleOut(BaseModel):
    name: str
    label: str
    color: Optional[str] = None
    is_builtin: bool
    permissions: list[str]

    model_config = {"from_attributes": True}


class RoleCreate(BaseModel):
    name: str
    label: str
    color: Optional[str] = None
    permissions: list[str] = []


class RoleUpdate(BaseModel):
    label: Optional[str] = None
    color: Optional[str] = None
    permissions: Optional[list[str]] = None


# ── Helpers ───────────────────────────────────────────────────────────────────

def _role_to_out(role: Role) -> dict:
    perms = role.permissions or []
    return {
        "name":       role.name,
        "label":      role.label,
        "color":      role.color,
        "is_builtin": role.is_builtin,
        "permissions": perms,
    }


def _reload_permissions(db: Session) -> None:
    """Reload ROLE_PERMISSIONS/TENANT_ROLE_OVERRIDES from DB."""
    roles = db.query(Role).all()
    load_roles_from_db(roles)


def _get_own_role(db: Session, tenant_id: str | None, role_name: str) -> Role | None:
    """Ligne appartenant explicitement à CE tenant (ou, en mode local sans
    tenant cloud, la ligne globale — la seule qui existe alors) — jamais une
    ligne d'un autre tenant, jamais le défaut plateforme d'un rôle intégré
    tant qu'il n'a pas été forké par ce tenant précis."""
    q = db.query(Role).filter(Role.name == role_name)
    q = q.filter(Role.tenant_id == tenant_id) if tenant_id else q.filter(Role.tenant_id.is_(None))
    return q.first()


def _get_global_default(db: Session, role_name: str) -> Role | None:
    return db.query(Role).filter(Role.tenant_id.is_(None), Role.name == role_name).first()


# ── Routes ────────────────────────────────────────────────────────────────────

@router.get("", response_model=list[RoleOut])
def list_roles(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.USERS_READ)),
):
    """Rôles visibles par CE tenant : ses propres lignes (forks de rôles
    intégrés + rôles personnalisés) + les défauts plateforme des rôles
    intégrés qu'il n'a pas encore forkés. Jamais les rôles d'un autre tenant
    — voir Role.py pour le détail du modèle tenant_id NULL vs renseigné."""
    tenant_id = current_user.tenant_id

    if not tenant_id:
        # Install locale sans tenant cloud : tout ce qui a tenant_id NULL est "à eux"
        roles = (
            db.query(Role).filter(Role.tenant_id.is_(None))
            .order_by(Role.is_builtin.desc(), Role.label).all()
        )
        return [_role_to_out(r) for r in roles]

    own_roles = db.query(Role).filter(Role.tenant_id == tenant_id).all()
    own_names = {r.name for r in own_roles}

    defaults_q = db.query(Role).filter(Role.tenant_id.is_(None), Role.is_builtin == True)  # noqa: E712
    if own_names:
        defaults_q = defaults_q.filter(~Role.name.in_(own_names))
    defaults = defaults_q.all()

    combined = own_roles + defaults
    combined.sort(key=lambda r: (not r.is_builtin, r.label))
    return [_role_to_out(r) for r in combined]


@router.post("", response_model=RoleOut, status_code=201)
def create_role(
    body: RoleCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.USERS_CREATE)),
):
    name = body.name.strip().lower().replace(" ", "_")
    if name == "admin":
        raise HTTPException(400, "Le nom 'admin' est réservé.")

    tenant_id = current_user.tenant_id

    # Un nom de rôle intégré ne se crée jamais ici — il se personnalise via
    # PUT /api/roles/{name}, qui fork le défaut plateforme pour ce tenant.
    if _get_global_default(db, name) is not None:
        raise HTTPException(400, f"'{name}' est un rôle intégré — modifiez-le plutôt via PUT.")

    if _get_own_role(db, tenant_id, name) is not None:
        raise HTTPException(400, f"Un rôle avec le nom '{name}' existe déjà.")

    role = Role(
        tenant_id=tenant_id,
        name=name,
        label=body.label.strip(),
        color=body.color,
        is_builtin=False,
        permissions=body.permissions,
    )
    db.add(role)
    db.commit()
    db.refresh(role)

    _reload_permissions(db)
    return _role_to_out(role)


@router.put("/{role_name}", response_model=RoleOut)
def update_role(
    role_name: str,
    body: RoleUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.USERS_UPDATE)),
):
    if role_name == "admin":
        raise HTTPException(403, "Le rôle admin ne peut pas être modifié.")

    tenant_id = current_user.tenant_id
    role = _get_own_role(db, tenant_id, role_name)

    if not role:
        # Pas encore de ligne propre à ce tenant — forker le défaut plateforme
        # s'il s'agit d'un rôle intégré (jamais pour un nom inconnu).
        global_role = _get_global_default(db, role_name)
        if not global_role:
            raise HTTPException(404, f"Rôle '{role_name}' introuvable.")
        if not tenant_id:
            # Install locale sans tenant cloud : une seule copie possible, on édite le défaut directement
            role = global_role
        else:
            role = Role(
                tenant_id=tenant_id,
                name=global_role.name,
                label=global_role.label,
                color=global_role.color,
                is_builtin=global_role.is_builtin,
                permissions=global_role.permissions,
            )
            db.add(role)

    if body.label is not None:
        if role.is_builtin:
            raise HTTPException(403, "Le label d'un rôle intégré ne peut pas être modifié.")
        role.label = body.label.strip()
    if body.color is not None:
        role.color = body.color
    if body.permissions is not None:
        role.permissions = body.permissions

    db.commit()
    db.refresh(role)

    _reload_permissions(db)
    return _role_to_out(role)


@router.delete("/{role_name}", status_code=204)
def delete_role(
    role_name: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.USERS_DELETE)),
):
    if role_name == "admin":
        raise HTTPException(403, "Le rôle admin ne peut pas être supprimé.")

    tenant_id = current_user.tenant_id
    role = _get_own_role(db, tenant_id, role_name)
    if not role:
        raise HTTPException(404, f"Rôle '{role_name}' introuvable.")

    # Supprimer le fork tenant d'un rôle intégré revient simplement à revenir
    # au défaut plateforme (list_roles retombera dessus automatiquement) —
    # seuls les VRAIS rôles intégrés globaux (tenant_id NULL) restent protégés.
    if role.is_builtin and role.tenant_id is None:
        raise HTTPException(403, "Les rôles intégrés ne peuvent pas être supprimés.")

    db.delete(role)
    db.commit()

    if tenant_id:
        TENANT_ROLE_OVERRIDES.pop((tenant_id, role_name), None)
    else:
        ROLE_PERMISSIONS.pop(role_name, None)
