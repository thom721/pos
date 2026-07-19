from sqlalchemy import Column, String, Integer, Enum as SAEnum, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class RestaurantTable(UUIDBase):
    __tablename__ = "restaurant_tables"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),    nullable=False, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'), nullable=True,  index=True)
    waiter_id    = Column(String(36), ForeignKey('users.id'),      nullable=True,  index=True)
    name         = Column(String(100), nullable=False)
    capacity     = Column(Integer, default=4)
    status       = Column(
        SAEnum('free', 'occupied', 'reserved', name='restaurant_table_status'),
        default='free',
        nullable=False,
    )

    waiter = relationship('User', foreign_keys=[waiter_id], lazy='joined')
