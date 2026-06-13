from sqlalchemy import Column, String, Numeric, Boolean, Integer, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.ext.hybrid import hybrid_property
from .base import UUIDBase

class Product(UUIDBase):
    __tablename__ = "products"

    category_id = Column(String(36), ForeignKey("categories.id"), nullable=False)
    supplier_id = Column(String(36), ForeignKey("suppliers.id"), nullable=True)

    barcode = Column(String(255), unique=True, index=True, nullable=True)
    name = Column(String(255), unique=True, index=True, nullable=False)
    purchase_price = Column(Numeric(12, 2))
    sale_price = Column(Numeric(12, 2), nullable=False)
    alert_stock = Column(Integer, default=0)
    description = Column(String(255) , nullable=True)
    is_active = Column(Boolean, default=True)
    image_url = Column(String(500), nullable=True)

    category = relationship("Category", back_populates="products")
    supplier = relationship("Supplier")
    stock_movements = relationship("StockMovement", back_populates="product")

    @hybrid_property
    def stock(self):
        return sum(m.quantity for m in self.stock_movements)
