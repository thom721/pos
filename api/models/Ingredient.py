from sqlalchemy import Column, String, ForeignKey
from .base import UUIDBase


class Ingredient(UUIDBase):
    __tablename__ = "ingredients"

    tenant_id   = Column(String(36), ForeignKey('tenants.id'),  nullable=False, index=True)
    name        = Column(String(100), nullable=False)
    product_id  = Column(String(36), ForeignKey('products.id'), nullable=True,  index=True)
    category_id = Column(String(36), ForeignKey('categories.id'), nullable=True, index=True)
