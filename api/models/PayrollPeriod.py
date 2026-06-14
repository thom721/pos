from sqlalchemy import Column, String, Numeric, Date, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class PayrollPeriod(UUIDBase):
    __tablename__ = "payroll_periods"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    reference         = Column(String(50),   unique=True, nullable=False, index=True)
    label             = Column(String(100),  nullable=False)          # "Juin 2026"
    period_start      = Column(Date,         nullable=False)
    period_end        = Column(Date,         nullable=False)
    pay_date          = Column(Date,         nullable=False)
    # "draft" | "processing" | "paid" | "cancelled"
    status            = Column(String(20),   nullable=False, default="draft")
    total_gross       = Column(Numeric(12, 2), nullable=False, default=0)
    total_deductions  = Column(Numeric(12, 2), nullable=False, default=0)
    total_net         = Column(Numeric(12, 2), nullable=False, default=0)
    notes             = Column(String(500),  nullable=True)
    created_by        = Column(String(36),   ForeignKey("users.id"), nullable=True)

    entries    = relationship("PayrollEntry",  back_populates="period", cascade="all, delete-orphan")
    creator    = relationship("User", foreign_keys=[created_by])
