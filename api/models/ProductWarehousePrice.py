from sqlalchemy import Column, String, Numeric, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from .base import UUIDBase


class ProductWarehousePrice(UUIDBase):
    """Prix de vente spécifique à un dépôt pour un produit — remplace
    Product.sale_price (le prix par défaut) uniquement pour ce dépôt.
    Absence de ligne = le produit utilise le prix par défaut à ce dépôt."""
    __tablename__ = "product_warehouse_prices"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),    nullable=True, index=True)
    product_id   = Column(String(36), ForeignKey('products.id'),   nullable=False, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'), nullable=False, index=True)
    sale_price   = Column(Numeric(12, 2), nullable=False)

    product   = relationship("Product")
    warehouse = relationship("Warehouse")

    __table_args__ = (
        UniqueConstraint("product_id", "warehouse_id", name="uq_product_warehouse_price"),
    )
