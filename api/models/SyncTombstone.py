from sqlalchemy import Column, String, ForeignKey, UniqueConstraint
from .base import UUIDBase


class SyncTombstone(UUIDBase):
    """Trace legere d'une suppression definitive sur une entite synchronisee.
    Le pull/push normal (filtre updated_at > since) ne peut jamais detecter
    qu'une ligne a disparu — une ligne supprimee n'a plus de ligne a filtrer.
    Sans tombstone, une suppression ne se propage jamais vers l'autre cote
    (bug reel constate sur ProductPriceTier : 3 paliers supprimes sur le
    cloud restaient indefiniment presents en local). UUIDBase fournit deja
    created_at/updated_at, utilises comme curseur de sync au meme titre que
    les autres entites (voir _get_sync_state dans local_sync_service.py)."""
    __tablename__ = "sync_tombstones"
    tenant_id   = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)
    entity_type = Column(String(50), nullable=False, index=True)
    record_id   = Column(String(36), nullable=False, index=True)

    __table_args__ = (
        UniqueConstraint('entity_type', 'record_id', name='uq_tombstone_entity_record'),
    )
