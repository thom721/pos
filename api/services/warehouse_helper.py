from sqlalchemy.orm import Session
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister


def bind_register_device(reg: PosRegister, new_device_id: str) -> None:
    """Assigne new_device_id à reg. Si l'appareil change réellement, révoque
    l'approbation — un appareil différent doit être ré-approuvé par un admin
    avant de pouvoir ouvrir une caisse (voir cashier_sessions.open_session).
    Ne rien faire si c'est le même appareil (préserve l'approbation)."""
    if reg.device_id != new_device_id:
        reg.is_device_approved = False
    reg.device_id = new_device_id


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
