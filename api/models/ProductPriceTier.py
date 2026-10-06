from sqlalchemy import Column, String, Numeric, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from .base import UUIDBase


class ProductPriceTier(UUIDBase):
    """Palier de prix d'un produit DANS un dépôt : à partir de `min_quantity`
    (unités de vente, ex: caisses), le prix unitaire est `price`.
    Le palier le plus élevé atteint par la quantité de la ligne s'applique.
    Absence de palier = prix de vente normal du dépôt."""
    __tablename__ = "product_price_tiers"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),    nullable=True, index=True)
    product_id   = Column(String(36), ForeignKey('products.id'),   nullable=False, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'), nullable=False, index=True)
    min_quantity = Column(Numeric(12, 2), nullable=False)
    price        = Column(Numeric(12, 2), nullable=False)

    product   = relationship("Product")
    warehouse = relationship("Warehouse")

    __table_args__ = (
        UniqueConstraint("product_id", "warehouse_id", "min_quantity", name="uq_product_warehouse_tier"),
    )
