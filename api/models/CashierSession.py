from sqlalchemy import Column, String, Numeric, ForeignKey, DateTime
from .base import UUIDBase


class CashierSession(UUIDBase):
    """
    One session = one cashier opening / closing a specific register.
    Tables created now; UI will come in a later phase.
    """
    __tablename__ = "cashier_sessions"

    tenant_id   = Column(String(36), ForeignKey('tenants.id'),      nullable=False, index=True)
    register_id = Column(String(36), ForeignKey('pos_registers.id'), nullable=False)
    cashier_id  = Column(String(36), ForeignKey('users.id'),         nullable=False)

    opened_at       = Column(DateTime(timezone=True), nullable=False)
    closed_at       = Column(DateTime(timezone=True), nullable=True)
    opening_balance = Column(Numeric(12, 2), default=0)
    closing_balance = Column(Numeric(12, 2), nullable=True)

    # 'open' | 'closed'
    status = Column(String(20), nullable=False, default='open')
