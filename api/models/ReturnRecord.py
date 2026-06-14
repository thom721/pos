from sqlalchemy import Column, String, Numeric, Text, ForeignKey
from .base import UUIDBase


class ReturnRecord(UUIDBase):
    """Tracks every processed return (sale or purchase) for history/listing."""
    __tablename__ = "return_records"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    return_type   = Column(String(20), nullable=False)   # 'sale' | 'purchase'
    reference_id  = Column(String(36), nullable=False)   # sale.id or purchase.id
    doc_reference = Column(String(100))                  # e.g. "VNT-XXXXXX"
    total_returned = Column(Numeric(12, 2), default=0)   # value of goods returned
    refund_amount  = Column(Numeric(12, 2), default=0)   # cash refunded (sales only)
    reason        = Column(Text, nullable=True)
    user_id       = Column(String(36), ForeignKey("users.id"), nullable=True)
    items_json    = Column(Text)  # JSON list of {product_name, quantity, unit_price}
