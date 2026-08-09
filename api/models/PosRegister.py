from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Integer, Text, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from .base import UUIDBase


class PosRegister(UUIDBase):
    __tablename__ = "pos_registers"

    tenant_id     = Column(String(36), ForeignKey('tenants.id'), nullable=False, index=True)
    warehouse_id  = Column(String(36), ForeignKey('warehouses.id'), nullable=True, index=True)
    name          = Column(String(100), nullable=False)
    device_id     = Column(String(36),  nullable=True)   # NULL until a device claims this slot
    # True par défaut (n'affecte pas rétroactivement les caisses déjà en usage) —
    # repassé à False dès qu'un device_id différent est assigné (voir
    # warehouse_helper.bind_register_device) ; un admin doit ré-approuver
    # explicitement avant que ce nouvel appareil puisse ouvrir une session
    # (voir cashier_sessions.open_session).
    is_device_approved = Column(Boolean, nullable=False, default=True)
    is_active     = Column(Boolean, nullable=False, default=True)
    # Session tracking
    session_token = Column(String(36), nullable=True)
    last_seen     = Column(DateTime(timezone=False), nullable=True)   # updated by heartbeat
    # Dernière version/build de l'app cliente ayant tapé ce endpoint —
    # permet à l'admin de voir qui tourne sur une version obsolète.
    app_version   = Column(String(20), nullable=True)
    app_build     = Column(Integer, nullable=True)

    # ── Abonnement par caisse ────────────────────────────────────────────────────
    # Toutes les caisses (initiales ou supplémentaires) ont leur propre ligne de
    # facturation. Les trois dates sont stockées chiffrées (Fernet, HKDF sur
    # register_id) pour protéger contre les modifications directes en base.
    is_initial               = Column(Boolean, nullable=False, default=False)
    _trial_ends_at           = Column('trial_ends_at',           Text(600), nullable=True)
    _subscription_started_at = Column('subscription_started_at', Text(600), nullable=True)
    _subscription_ends_at    = Column('subscription_ends_at',    Text(600), nullable=True)

    # Caissier dédié : seul cet utilisateur peut ouvrir une session sur cette caisse.
    dedicated_user_id = Column(String(36), ForeignKey('users.id'), nullable=True, index=True)

    warehouse       = relationship("Warehouse", back_populates="pos_registers")
    dedicated_user  = relationship("User", foreign_keys=[dedicated_user_id], lazy="joined")

    __table_args__ = (
        UniqueConstraint('tenant_id', 'device_id', name='uq_register_tenant_device'),
        UniqueConstraint('warehouse_id', 'name', name='uq_register_name_warehouse'),
    )

    # ── Constructeur — gère les dates chiffrées ───────────────────────────────
    def __init__(self, **kwargs):
        import uuid as _uuid
        # Le default de UUIDBase s'applique au INSERT, pas à la construction.
        # On génère l'id ici pour pouvoir s'en servir comme sel Fernet.
        if 'id' not in kwargs:
            kwargs['id'] = str(_uuid.uuid4())
        trial       = kwargs.pop('trial_ends_at', None)
        sub_start   = kwargs.pop('subscription_started_at', None)
        sub_end     = kwargs.pop('subscription_ends_at', None)
        super().__init__(**kwargs)   # self.id est maintenant défini
        if trial     is not None: self.trial_ends_at           = trial
        if sub_start is not None: self.subscription_started_at = sub_start
        if sub_end   is not None: self.subscription_ends_at    = sub_end

    # ── Propriétés chiffrées (transparentes pour le reste du code) ────────────
    @property
    def trial_ends_at(self) -> datetime | None:
        return self._dec(self._trial_ends_at)

    @trial_ends_at.setter
    def trial_ends_at(self, value: datetime | None):
        self._trial_ends_at = self._enc(value)

    @property
    def subscription_started_at(self) -> datetime | None:
        return self._dec(self._subscription_started_at)

    @subscription_started_at.setter
    def subscription_started_at(self, value: datetime | None):
        self._subscription_started_at = self._enc(value)

    @property
    def subscription_ends_at(self) -> datetime | None:
        return self._dec(self._subscription_ends_at)

    @subscription_ends_at.setter
    def subscription_ends_at(self, value: datetime | None):
        self._subscription_ends_at = self._enc(value)

    # ── Helpers internes ──────────────────────────────────────────────────────
    def _enc(self, dt: datetime | None) -> str | None:
        if dt is None:
            return None
        from api.core.billing_crypto import encrypt_register_date
        return encrypt_register_date(dt, self.id)

    def _dec(self, token: str | None) -> datetime | None:
        if not token:
            return None
        from api.core.billing_crypto import try_decrypt_register_date
        return try_decrypt_register_date(token, self.id)
