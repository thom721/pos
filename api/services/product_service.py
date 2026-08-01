import logging
from typing import List, Optional, Union
from sqlalchemy.orm import Session, joinedload, selectinload
from sqlalchemy import or_
from fastapi import HTTPException
from api.models.Product import Product
from api.models.Category import Category
from api.models.Supplier import Supplier
from api.models.ProductWarehousePrice import ProductWarehousePrice
from api.schemas.product import ProductCreate, ProductUpdate, ProductRead
from api.services.base_service import TenantService
from api.services.stock_service import stock_map as _stock_map

logger = logging.getLogger(__name__)


def _price_map(db: Session, product_ids: list[str], warehouse_id: Optional[str]) -> dict[str, float]:
    """{product_id: prix override} pour les produits ayant un prix spécifique
    à ce dépôt — absents du dict = utilisent Product.sale_price par défaut."""
    if not warehouse_id or not product_ids:
        return {}
    rows = db.query(ProductWarehousePrice).filter(
        ProductWarehousePrice.product_id.in_(product_ids),
        ProductWarehousePrice.warehouse_id == warehouse_id,
    ).all()
    return {r.product_id: float(r.sale_price) for r in rows}


def resolve_price(db: Session, product: Product, warehouse_id: Optional[str]) -> float:
    """Prix effectif d'UN produit à un dépôt donné — utilisé par create_sale
    quand aucun unit_price explicite n'est fourni par le client."""
    if not warehouse_id:
        return float(product.sale_price)
    override = db.query(ProductWarehousePrice).filter_by(
        product_id=product.id, warehouse_id=warehouse_id,
    ).first()
    return float(override.sale_price) if override else float(product.sale_price)


class ProductService(TenantService):
    def __init__(self, db: Session, tenant_id: str | None = None):
        super().__init__(db, tenant_id)

    def create(self, data: Union[ProductCreate, List[ProductCreate], dict, List[dict]]):
        if not isinstance(data, list):
            data = [data]

        products = []

        for item in data:
            payload = item if isinstance(item, dict) else item.dict()

            # Vérifie l'unicité avant insertion (tenant-scoped)
            exists = self._q(Product).filter(Product.name == payload["name"]).first()
            if exists:
                raise HTTPException(400, f"Un produit nommé '{payload['name']}' existe déjà")

            # Vérifie que la catégorie existe
            if not self.db.get(Category, str(payload.get("category_id", ""))):
                raise HTTPException(400, "Catégorie introuvable")

            # Vérifie le fournisseur si fourni
            supplier_id = payload.get("supplier_id")
            if supplier_id and not self.db.get(Supplier, str(supplier_id)):
                raise HTTPException(400, "Fournisseur introuvable")

            product = Product(**payload)
            self._set_tenant(product)
            self.db.add(product)
            products.append(product)

        try:
            self.db.commit()
        except Exception as e:
            self.db.rollback()
            logger.error("Erreur création produit: %s", e, exc_info=True)
            raise HTTPException(500, "Erreur lors de la création du produit")

        for product in products:
            self.db.refresh(product)

        return products[0] if len(products) == 1 else products

    def get(self, product_id: str) -> Optional[Product]:
        return (
            self._q(Product)
            .options(selectinload(Product.stock_movements))
            .filter(Product.id == product_id)
            .first()
        )

    def list(self, page: int = 1, per_page: int = 5, search: Optional[str] = None,
             category_id: Optional[str] = None, exclude_locked: bool = False,
             warehouse_id: Optional[str] = None, restrict_to_warehouse: bool = True):
        # selectinload pour les collections (évite le problème joinedload + pagination)
        query = self._q(Product).options(
            joinedload(Product.category),
            selectinload(Product.stock_movements),
        )

        if search:
            query = query.filter(
                or_(
                    Product.name.ilike(f"%{search}%"),
                    Product.barcode.ilike(f"%{search}%"),
                )
            )

        if category_id:
            query = query.filter(Product.category_id == category_id)

        if exclude_locked:
            query = query.filter(Product.is_locked == False)  # noqa: E712

        if warehouse_id and restrict_to_warehouse:
            # Un produit rattaché à UN dépôt précis (Product.warehouse_id) est
            # masqué des autres dépôts — produits sans dépôt (NULL) restent
            # visibles partout. Désactivé pour l'Entrepôt (restrict_to_warehouse
            # =False) qui doit voir tous les produits pour pouvoir les distribuer.
            query = query.filter(
                or_(Product.warehouse_id.is_(None), Product.warehouse_id == warehouse_id)
            )

        total = query.count()
        items = query.offset((page - 1) * per_page).limit(per_page).all()

        data = items
        if warehouse_id:
            # `stock`/`sale_price` reflètent alors le dépôt demandé plutôt que
            # le total/prix par défaut du tenant — utilisé par l'écran
            # Entrepôt et, côté caisse/produits, par le dépôt actif
            # (Product.stock/sale_price restent les valeurs globales/par
            # défaut par ailleurs).
            ids = [p.id for p in items]
            stocks = _stock_map(self.db, ids, tenant_id=self._tid, warehouse_id=warehouse_id)
            prices = _price_map(self.db, ids, warehouse_id)
            data = [
                ProductRead.model_validate(p).model_copy(update={
                    "stock": stocks.get(p.id, 0.0),
                    "sale_price": prices.get(p.id, float(p.sale_price)),
                })
                for p in items
            ]

        return {
            "page": page,
            "per_page": per_page,
            "total": total,
            "data": data,
        }

    def update(self, product_id: str, data: ProductUpdate) -> Optional[Product]:
        product = self.get(product_id)
        if not product:
            return None
        for field, value in data.dict(exclude_unset=True).items():
            setattr(product, field, value)
        self.db.commit()
        self.db.refresh(product)
        return product

    def delete(self, product_id: str) -> bool:
        product = self.get(product_id)
        if not product:
            return False
        self.db.delete(product)
        self.db.commit()
        return True

    # ── Prix par dépôt ────────────────────────────────────────────────────

    def get_warehouse_prices(self, product_id: str) -> List[ProductWarehousePrice]:
        return self.db.query(ProductWarehousePrice).filter(
            ProductWarehousePrice.product_id == product_id
        ).all()

    def set_warehouse_price(self, product_id: str, warehouse_id: str, sale_price: float) -> ProductWarehousePrice:
        existing = self.db.query(ProductWarehousePrice).filter_by(
            product_id=product_id, warehouse_id=warehouse_id,
        ).first()
        if existing:
            existing.sale_price = sale_price
        else:
            existing = ProductWarehousePrice(
                product_id=product_id, warehouse_id=warehouse_id, sale_price=sale_price,
            )
            self._set_tenant(existing)
            self.db.add(existing)
        self.db.commit()
        self.db.refresh(existing)
        return existing

    def delete_warehouse_price(self, product_id: str, warehouse_id: str) -> bool:
        existing = self.db.query(ProductWarehousePrice).filter_by(
            product_id=product_id, warehouse_id=warehouse_id,
        ).first()
        if not existing:
            return False
        self.db.delete(existing)
        self.db.commit()
        return True
