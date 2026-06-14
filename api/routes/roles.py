from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional

from api.database import get_db
from api.dependencies.auth import require_permission
from api.models.User import User
from api.models.Role import Role
from api.core.permissions import P, ROLE_PERMISSIONS, load_roles_from_db

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
    """Reload ROLE_PERMISSIONS from DB."""
    roles = db.query(Role).all()
    load_roles_from_db(roles)


# ── Routes ────────────────────────────────────────────────────────────────────

@router.get("", response_model=list[RoleOut])
def list_roles(
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.USERS_READ)),
):
    roles = db.query(Role).order_by(Role.is_builtin.desc(), Role.label).all()
    return [_role_to_out(r) for r in roles]


@router.post("", response_model=RoleOut, status_code=201)
def create_role(
    body: RoleCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permission(P.USERS_CREATE)),
):
    name = body.name.strip().lower().replace(" ", "_")
    if db.query(Role).filter(Role.name == name).first():
        raise HTTPException(400, f"Un rôle avec le nom '{name}' existe déjà.")

    role = Role(
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
    _: User = Depends(require_permission(P.USERS_UPDATE)),
):
    if role_name == "admin":
        raise HTTPException(403, "Le rôle admin ne peut pas être modifié.")

    role = db.query(Role).filter(Role.name == role_name).first()
    if not role:
        raise HTTPException(404, f"Rôle '{role_name}' introuvable.")

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
    _: User = Depends(require_permission(P.USERS_DELETE)),
):
    if role_name == "admin":
        raise HTTPException(403, "Le rôle admin ne peut pas être supprimé.")

    role = db.query(Role).filter(Role.name == role_name).first()
    if not role:
        raise HTTPException(404, f"Rôle '{role_name}' introuvable.")
    if role.is_builtin:
        raise HTTPException(403, "Les rôles intégrés ne peuvent pas être supprimés.")

    db.delete(role)
    db.commit()

    ROLE_PERMISSIONS.pop(role_name, None)
