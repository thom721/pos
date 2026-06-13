# from sqlalchemy import Column, Integer, Numeric, ForeignKey,String
# # from app.database import .base
# from .base import UUIDBase

# class SaleItem(UUIDBase):
#     __tablename__ = "sale_items"

# #     id = Column(Integer, primary_key=True)
#     sale_id = Column(String(36), ForeignKey("sales.id", ondelete="CASCADE"))
#     product_id = Column(String(36), ForeignKey("products.id", ondelete="CASCADE"))

#     quantity = Column(Integer)
#     unit_price = Column(Numeric(12, 2))
#     subtotal = Column(Numeric(12, 2))

from sqlalchemy import Column, String, Integer, Numeric, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase

class SaleItem(UUIDBase):
    __tablename__ = "sale_items"

    sale_id = Column(String(36), ForeignKey("sales.id"))
    product_id = Column(String(36), ForeignKey("products.id"))

    quantity = Column(Numeric(12, 2), nullable=False)
    unit_price = Column(Numeric(12, 2), nullable=False)
    original_price = Column(Numeric(12, 2), nullable=True)
    subtotal = Column(Numeric(12, 2), nullable=False)

    sale = relationship("Sale", back_populates="items")
    product = relationship("Product")

