from sqlalchemy import Column, String
from sqlalchemy.orm import relationship
from .base import UUIDBase

class Category(UUIDBase):
    __tablename__ = "categories"

    name = Column(String(255), unique=True, nullable=False)
    cat_description = Column(String(255) , nullable=True)

    products = relationship("Product", back_populates="category")
