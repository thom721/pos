from sqlalchemy import Column, String, Boolean, Numeric, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class ModifierGroup(UUIDBase):
    __tablename__ = "modifier_groups"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),     nullable=False, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'),  nullable=True,  index=True)
    name         = Column(String(100), nullable=False)
    product_id   = Column(String(36), ForeignKey('products.id'),    nullable=True, index=True)
    menu_item_id = Column(String(36), ForeignKey('menu_items.id'),  nullable=True, index=True)
    category_id  = Column(String(36), ForeignKey('categories.id'),  nullable=True, index=True)
    required     = Column(Boolean, default=False, nullable=False)
    multi_select = Column(Boolean, default=True,  nullable=False)

    options = relationship(
        'ModifierOption', back_populates='group',
        cascade='all, delete-orphan', lazy='joined',
        order_by='ModifierOption.name',
    )


class ModifierOption(UUIDBase):
    __tablename__ = "modifier_options"

    tenant_id   = Column(String(36), ForeignKey('tenants.id'),         nullable=True,  index=True)
    group_id    = Column(String(36), ForeignKey('modifier_groups.id'), nullable=False, index=True)
    name        = Column(String(100), nullable=False)
    extra_price = Column(Numeric(10, 2), default=0, nullable=False)

    group = relationship('ModifierGroup', back_populates='options')
