import logging

from sqlalchemy.orm import Session
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister

_log = logging.getLogger("pos.register")


def bind_register_device(reg: PosRegister, new_device_id: str, *, reason: str = "unknown") -> None:
    """Assigne new_device_id à reg. Si l'appareil change réellement, révoque
    l'approbation — un appareil différent doit être ré-approuvé par un admin
    avant de pouvoir ouvrir une caisse (voir cashier_sessions.open_session).
    Ne rien faire si c'est le même appareil (préserve l'approbation).

    session_token est aussi remis à None dans ce cas : il appartenait à
    l'ancien device_id (posé uniquement par cloud_login, voir tenant_service.py)
    et n'a plus de sens pour le nouveau — le laisser tel quel faisait échouer
    la vérification anti-vol de session sur la toute prochaine requête du
    véritable utilisateur courant (get_current_user comparait ce token
    périmé au sid de son propre JWT, encore valide, et le déconnectait à
    tort avec "une autre connexion a été ouverte").

    Logué systématiquement (reason = point d'appel) — bug rapporté plusieurs
    fois en prod où un appareil déjà approuvé se retrouve réattribué à une
    autre caisse sans explication ; ce log est la seule façon de savoir,
    après coup, quel chemin de code a fait le changement.
    """
    if reg.device_id != new_device_id:
        _log.info(
            "bind_register_device: reg=%s (%s) tenant=%s device_id %r -> %r "
            "(reason=%s) — is_device_approved remis a False",
            reg.id, reg.name, reg.tenant_id, reg.device_id, new_device_id, reason,
        )
        reg.is_device_approved = False
        reg.session_token = None
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
