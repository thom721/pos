from sqlalchemy import Column, String, Numeric, Boolean, Time, Enum, ForeignKey, UniqueConstraint
import enum
from .base import UUIDBase


class DiscountType(enum.Enum):
    percentage = "percentage"
    fixed = "fixed"


class DiscountScope(enum.Enum):
    receipt = "receipt"
    item = "item"
    both = "both"


class Discount(UUIDBase):
    __tablename__ = "discounts"
    __table_args__ = (
        UniqueConstraint('tenant_id', 'name', name='uq_discount_tenant_name'),
    )

    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    name  = Column(String(255), nullable=False)
    type  = Column(Enum(DiscountType), nullable=False)
    value = Column(Numeric(12, 2), nullable=False)
    scope = Column(Enum(DiscountScope), nullable=False, default=DiscountScope.both)

    is_automatic = Column(Boolean, default=False, nullable=False)
    is_active    = Column(Boolean, default=True, nullable=False)

    # Fenêtre d'application pour les rabais automatiques ("happy hour").
    # NULL = pas de restriction sur ce critère.
    schedule_days  = Column(String(20), nullable=True)  # "0,1,2,3,4" (0=lundi)
    schedule_start = Column(Time, nullable=True)
    schedule_end   = Column(Time, nullable=True)

    # Quantité minimale (rabais article) — ex: à partir de 3 unités.
    # NULL = pas de minimum. N'a de sens que pour scope item/both.
    min_quantity = Column(Numeric(12, 2), nullable=True)
