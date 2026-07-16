from sqlalchemy.orm import Session
from api.models.Warehouse import Warehouse


def resolve_warehouse_id(db: Session, tenant_id: str, warehouse_id: str | None = None) -> str | None:
    """
    Retourne warehouse_id si fourni (et appartient au tenant),
    sinon retourne le depot par defaut du tenant.
    Retourne None si aucun depot trouve (mode sans multi-depot).
    """
    if warehouse_id:
        ok = db.query(Warehouse.id).filter(
            Warehouse.id == warehouse_id,
            Warehouse.tenant_id == tenant_id,
            Warehouse.is_active == True,  # noqa: E712
        ).first()
        return warehouse_id if ok else None

    default = db.query(Warehouse.id).filter(
        Warehouse.tenant_id == tenant_id,
        Warehouse.is_default == True,  # noqa: E712
        Warehouse.is_active == True,   # noqa: E712
    ).first()
    return default[0] if default else None
