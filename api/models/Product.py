from sqlalchemy import Column, String, Numeric, Boolean, Integer, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.ext.hybrid import hybrid_property
from .base import UUIDBase

class Product(UUIDBase):
    __tablename__ = "products"
    tenant_id    = Column(String(36), ForeignKey('tenants.id'),    nullable=True, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'), nullable=True, index=True)

    category_id = Column(String(36), ForeignKey("categories.id"), nullable=False)
    supplier_id = Column(String(36), ForeignKey("suppliers.id"), nullable=True)

    barcode = Column(String(255), index=True, nullable=True)
    name = Column(String(255), index=True, nullable=False)
    purchase_price = Column(Numeric(12, 2))
    sale_price = Column(Numeric(12, 2), nullable=False)
    alert_stock = Column(Integer, default=0)
    description = Column(String(255) , nullable=True)
    is_active = Column(Boolean, default=True)
    is_locked = Column(Boolean, default=False, nullable=False)
    image_url = Column(String(500), nullable=True)

    # ── Produit composé (ex: "Caisse" = 12 x "Boîte lait") ────────────────────
    # component_product_id pointe vers le produit dont le stock réel est suivi
    # (l'unité de vérité) ; component_quantity = combien d'unités du composant
    # équivalent à 1 unité de ce produit-ci. Un produit composé n'a jamais de
    # mouvements de stock propres — son stock est toujours dérivé de celui du
    # composant (voir la propriété `stock` ci-dessous).
    component_product_id = Column(String(36), ForeignKey("products.id"), nullable=True)
    component_quantity   = Column(Numeric(12, 4), nullable=True)

    category = relationship("Category", back_populates="products")
    supplier = relationship("Supplier")
    stock_movements = relationship("StockMovement", back_populates="product")
    component = relationship("Product", remote_side="Product.id", foreign_keys=[component_product_id])

    __table_args__ = (
        UniqueConstraint("name",    "tenant_id", name="uq_product_name_tenant"),
        UniqueConstraint("barcode", "tenant_id", name="uq_product_barcode_tenant"),
    )

    @hybrid_property
    def is_composite(self):
        return self.component_product_id is not None and self.component_quantity is not None

    @hybrid_property
    def stock(self):
        if self.is_composite:
            comp_stock = sum(m.quantity for m in self.component.stock_movements) if self.component else 0
            return int(comp_stock // self.component_quantity)
        return sum(m.quantity for m in self.stock_movements)
