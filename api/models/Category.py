from sqlalchemy import ForeignKey, Column, String
from sqlalchemy.orm import relationship
from .base import UUIDBase

class Category(UUIDBase):
    __tablename__ = "categories"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    name = Column(String(255), unique=True, nullable=False)
    cat_description = Column(String(255) , nullable=True)

    products = relationship("Product", back_populates="category")
