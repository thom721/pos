from sqlalchemy import Column, String, Integer, Text, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class InventoryRecord(UUIDBase):
    __tablename__ = "inventory_records"
    tenant_id    = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)
    warehouse_id = Column(String(36), ForeignKey("warehouses.id"), nullable=True, index=True)

    reference         = Column(String(100), nullable=False)
    inventory_type    = Column(String(20),  nullable=False)  # 'full' | 'partial'
    status            = Column(String(20),  nullable=False, default="confirmed")
    notes             = Column(Text, nullable=True)
    total_products    = Column(Integer, default=0)
    discrepancy_count = Column(Integer, default=0)
    user_id           = Column(String(36), ForeignKey("users.id"), nullable=True)
    items_json        = Column(Text)  # JSON list of counted items with diffs

    warehouse = relationship("Warehouse", back_populates="inventory_records")
