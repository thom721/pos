from datetime import datetime
from sqlalchemy import Column, String, Boolean, Text, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from .base import UUIDBase


class Warehouse(UUIDBase):
    __tablename__ = "warehouses"

    tenant_id   = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)
    name        = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    address     = Column(String(255), nullable=True)
    is_active   = Column(Boolean, nullable=False, default=True)
    is_default  = Column(Boolean, nullable=False, default=False)
    is_claimed  = Column(Boolean, nullable=False, default=False)
    # Entrepôt central (stock de transit, distribué vers les dépôts de vente) —
    # un tenant peut en créer plusieurs. Exclu du décompte de facturation des
    # dépôts (api/routes/billing.py::_compute_plan_usage) mais volontairement
    # PAS exclu de la liste générale des dépôts (sert de destination de
    # réception d'achat comme n'importe quel dépôt).
    is_entrepot = Column(Boolean, nullable=False, default=False)

    # Dépôt de vente auquel cet entrepôt est rattaché (uniquement pertinent
    # quand is_entrepot=True) — sert de clé de synchro stable (au lieu du nom,
    # non fiable : deux installations peuvent créer un entrepôt "Entrepôt"
    # indépendamment, sans jamais se fusionner) ET de règle de portée : un
    # entrepôt sans dépôt rattaché n'est jamais synchronisé vers le local,
    # il reste consultable uniquement depuis le cloud (voir api/routes/sync.py
    # sync_pull / sync_pull_batch).
    linked_warehouse_id = Column(String(36), ForeignKey('warehouses.id'), nullable=True)

    # ── Abonnement par entrepôt ────────────────────────────────────────────────
    # Un entrepôt n'a PAS d'essai gratuit : NULL = jamais payé. Distribuer du
    # stock (entrepôt → dépôts) est bloqué tant que non payé (voir
    # entrepot_service.py). Chiffré (Fernet, HKDF sur warehouse_id) comme
    # PosRegister.subscription_ends_at — même raisonnement, voir ce modèle.
    _subscription_ends_at = Column('subscription_ends_at', Text(600), nullable=True)

    stock_movements    = relationship("StockMovement",    back_populates="warehouse")
    purchases          = relationship("Purchase",         back_populates="warehouse")
    purchase_receipts  = relationship("PurchaseReceipt",  back_populates="warehouse")
    inventory_records  = relationship("InventoryRecord",  back_populates="warehouse")
    pos_registers      = relationship("PosRegister",      back_populates="warehouse")
    sales              = relationship("Sale",             back_populates="warehouse")
    cashier_sessions   = relationship("CashierSession",   back_populates="warehouse")
    return_records     = relationship("ReturnRecord",     back_populates="warehouse")

    __table_args__ = (
        UniqueConstraint("name", "tenant_id", name="uq_warehouse_name_tenant"),
    )

    def __init__(self, **kwargs):
        import uuid as _uuid
        if 'id' not in kwargs:
            kwargs['id'] = str(_uuid.uuid4())
        sub_end = kwargs.pop('subscription_ends_at', None)
        super().__init__(**kwargs)
        if sub_end is not None:
            self.subscription_ends_at = sub_end

    @property
    def subscription_ends_at(self) -> datetime | None:
        if not self._subscription_ends_at:
            return None
        from api.core.billing_crypto import try_decrypt_register_date
        return try_decrypt_register_date(self._subscription_ends_at, self.id)

    @subscription_ends_at.setter
    def subscription_ends_at(self, value: datetime | None):
        if value is None:
            self._subscription_ends_at = None
            return
        from api.core.billing_crypto import encrypt_register_date
        self._subscription_ends_at = encrypt_register_date(value, self.id)
