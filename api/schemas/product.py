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
    supplier_id: Optional[str] = None
    category_id: Optional[str]
    warehouse_id: Optional[str] = None
    # Produit composé (ex: "Caisse" = 12 x "Boîte") — component_product_id
    # référence le produit dont le stock est réellement suivi ; ce produit-ci
    # n'a alors plus de stock propre (dérivé du composant).
    component_product_id: Optional[str] = None
    component_quantity: Optional[float] = None


class ProductCreate(ProductBase):
    pass

class ProductRead(ProductBase):
    id: str
    image_url: Optional[str] = None
    stock: Optional[float] = None
    category: Optional[CategoryRead] = None
    is_locked: bool = False

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
    warehouse_id: Optional[str] = None
    is_locked: Optional[bool] = None
    component_product_id: Optional[str] = None
    component_quantity: Optional[float] = None


class ProductSaleItem(BaseModel):
    id: str
    name: str
    barcode: str | None
    sale_price: float
    alert_stock: int
    category: Optional[CategoryRead] = None

class CategoryResponse(BaseModel):
    # id: str
    name: str

    class Config:
        from_attributes = True
 