from sqlalchemy import Column, String, Numeric, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from .base import UUIDBase


class CashierSession(UUIDBase):
    """One session = one cashier opening / closing a specific register."""
    __tablename__ = "cashier_sessions"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),       nullable=False, index=True)
    register_id  = Column(String(36), ForeignKey('pos_registers.id'), nullable=False)
    cashier_id   = Column(String(36), ForeignKey('users.id'),         nullable=False)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'),    nullable=True, index=True)

    warehouse = relationship("Warehouse", back_populates="cashier_sessions")

    opened_at       = Column(DateTime(timezone=True), nullable=False)
    closed_at       = Column(DateTime(timezone=True), nullable=True)
    opening_balance = Column(Numeric(12, 2), default=0)
    closing_balance = Column(Numeric(12, 2), nullable=True)

    # 'open' | 'closed'
    status = Column(String(20), nullable=False, default='open')

    # ── Reconciliation fields (filled at close) ────────────────────────────
    total_cash_sales          = Column(Numeric(12, 2), nullable=True)
    total_card_sales          = Column(Numeric(12, 2), nullable=True)
    total_mobile_sales        = Column(Numeric(12, 2), nullable=True)
    total_bank_sales          = Column(Numeric(12, 2), nullable=True)
    total_refunds_cash        = Column(Numeric(12, 2), nullable=True)
    expected_closing_balance  = Column(Numeric(12, 2), nullable=True)
    cash_difference           = Column(Numeric(12, 2), nullable=True)  # closing - expected
