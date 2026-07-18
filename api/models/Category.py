from sqlalchemy import ForeignKey, Column, String, UniqueConstraint
from sqlalchemy.orm import relationship
from .base import UUIDBase

class Category(UUIDBase):
    __tablename__ = "categories"
    __table_args__ = (
        UniqueConstraint('tenant_id', 'name', name='uq_category_tenant_name'),
    )

    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    name = Column(String(255), nullable=False)
    description = Column(String(255), nullable=True)

    products = relationship("Product", back_populates="category")
