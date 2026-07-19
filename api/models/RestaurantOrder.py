from sqlalchemy import Column, String, Numeric, Integer, Enum as SAEnum, ForeignKey, Text
from sqlalchemy.orm import relationship
from .base import UUIDBase


class RestaurantOrder(UUIDBase):
    __tablename__ = "restaurant_orders"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),           nullable=False, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'),        nullable=True,  index=True)
    table_id     = Column(String(36), ForeignKey('restaurant_tables.id'), nullable=True,  index=True)
    cashier_id   = Column(String(36), ForeignKey('users.id'),             nullable=True)
    status       = Column(
        SAEnum('open', 'sent_to_kitchen', 'ready', 'closed', name='restaurant_order_status'),
        default='open',
        nullable=False,
    )
    covers  = Column(Integer, default=1, nullable=False)
    notes   = Column(Text, nullable=True)
    tip     = Column(Numeric(10, 2), default=0, nullable=False)
    sale_id = Column(String(36), ForeignKey('sales.id'), nullable=True)

    items = relationship('RestaurantOrderItem', back_populates='order',
                         cascade='all, delete-orphan', lazy='joined')
    table = relationship('RestaurantTable', lazy='joined')


class RestaurantOrderItem(UUIDBase):
    __tablename__ = "restaurant_order_items"

    order_id      = Column(String(36), ForeignKey('restaurant_orders.id'), nullable=False, index=True)
    product_id    = Column(String(36), ForeignKey('products.id'),          nullable=True)
    menu_item_id  = Column(String(36), ForeignKey('menu_items.id'),        nullable=True)
    quantity      = Column(Numeric(10, 2), default=1, nullable=False)
    unit_price    = Column(Numeric(10, 2), nullable=False)
    notes         = Column(String(255), nullable=True)
    status        = Column(
        SAEnum('pending', 'preparing', 'ready', name='restaurant_item_status'),
        default='pending',
        nullable=False,
    )

    order     = relationship('RestaurantOrder', back_populates='items')
    product   = relationship('Product',  lazy='joined', foreign_keys=[product_id])
    menu_item = relationship('MenuItem', lazy='joined', foreign_keys=[menu_item_id])
