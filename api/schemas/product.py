from pydantic import BaseModel
from typing import List, Optional  
from .category import CategoryRead 
 

# 🔹 Product
# ===== Product Schemas =====
class ProductBase(BaseModel):
    name: str
    description: Optional[str] = None 
    purchase_price: float
    sale_price: float
    alert_stock: int
    barcode: Optional[str] = None   
    supplier_id: Optional[str] = None  # FK vers Supplier
    category_id: Optional[str]  # FK vers Category


class ProductCreate(ProductBase):
    pass

class ProductRead(ProductBase):
    id: str
    image_url: Optional[str] = None
    category: CategoryRead

    class Config:
        from_attributes = True

class ProductUpdate(BaseModel):
    name: Optional[str]
    description: Optional[str] = None
    purchase_price: float
    sale_price: float
    alert_stock: int
    barcode: Optional[str] = None
    supplier_id: Optional[str] = None
    category_id: Optional[str]
 

class ProductSaleItem(BaseModel):
    id: str
    name: str
    barcode: str | None
    sale_price: float
    alert_stock: int
    category: CategoryRead

class CategoryResponse(BaseModel):
    # id: str
    name: str

    class Config:
        from_attributes = True
 