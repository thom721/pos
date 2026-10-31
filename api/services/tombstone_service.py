from sqlalchemy.orm import Session

from api.models.SyncTombstone import SyncTombstone
from api.core.dt_coerce import now_local


def record_deletion(db: Session, entity_type: str, record_id, tenant_id: str | None = None) -> None:
    """A appeler CHAQUE FOIS qu'une ligne d'une entite listee dans
    SYNC_ENTITIES est supprimee definitivement — AVANT le commit qui
    supprime la ligne elle-meme, dans la MEME transaction (db.add ici,
    db.delete(obj) a cote, un seul db.commit() a la fin). Sans cet appel,
    la suppression n'est jamais visible par l'autre cote : le pull/push
    normal ne filtre que sur updated_at, une ligne supprimee n'a plus de
    ligne a filtrer."""
    record_id = str(record_id)
    existing = db.query(SyncTombstone).filter_by(
        entity_type=entity_type, record_id=record_id,
    ).first()
    if existing:
        existing.updated_at = now_local()
        if tenant_id and not existing.tenant_id:
            existing.tenant_id = tenant_id
        return
    db.add(SyncTombstone(
        entity_type=entity_type, record_id=record_id, tenant_id=tenant_id,
    ))
