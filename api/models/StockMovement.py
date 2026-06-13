from sqlalchemy import Column, String, Enum, ForeignKey, Text, Numeric, Index
from sqlalchemy.orm import relationship
import enum
from .base import UUIDBase


class StockType(enum.Enum):
    in_ = "in"
    out = "out"
    adjust = "adjust"


class StockMovement(UUIDBase):
    __tablename__ = "stock_movements"

    product_id  = Column(String(36), ForeignKey("products.id"))
    user_id     = Column(String(36), ForeignKey("users.id"))
    type        = Column(Enum(StockType))
    quantity    = Column(Numeric(12, 2), nullable=False)
    source_type = Column(String(50))
    source_id   = Column(String(36))
    note        = Column(Text)

    product = relationship("Product", back_populates="stock_movements")
    user    = relationship("User")

    __table_args__ = (
        Index("idx_sm_product_source", "product_id", "source_type"),
        Index("idx_sm_source_id",      "source_id", "source_type"),
        Index("idx_sm_created_at",     "created_at"),
    )
