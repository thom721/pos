from sqlalchemy import Column, String, ForeignKey
from .base import UUIDBase


class RoomAttribute(UUIDBase):
    __tablename__ = "room_attributes"

    tenant_id = Column(String(36), ForeignKey('tenants.id'),          nullable=False, index=True)
    table_id  = Column(String(36), ForeignKey('restaurant_tables.id'), nullable=False, index=True)
    key       = Column(String(100), nullable=False)
    value     = Column(String(255), nullable=False, default='')
