from sqlalchemy import Column, String, Boolean, Numeric, Text, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class MenuItem(UUIDBase):
    __tablename__ = "menu_items"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),     nullable=False, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'),  nullable=True,  index=True)
    name         = Column(String(150), nullable=False)
    description  = Column(Text, nullable=True)
    price        = Column(Numeric(10, 2), nullable=False, default=0)
    category_id  = Column(String(36), ForeignKey('categories.id'),  nullable=True, index=True)
    product_id   = Column(String(36), ForeignKey('products.id'),    nullable=True, index=True)
    available    = Column(Boolean, default=True, nullable=False)
    image_url    = Column(String(500), nullable=True)

    category = relationship('Category', lazy='joined')
    product  = relationship('Product',  lazy='joined')
