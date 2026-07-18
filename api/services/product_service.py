import logging
from typing import List, Optional, Union
from sqlalchemy.orm import Session, joinedload, selectinload
from sqlalchemy import or_
from fastapi import HTTPException
from api.models.Product import Product
from api.models.Category import Category
from api.models.Supplier import Supplier
from api.schemas.product import ProductCreate, ProductUpdate
from api.services.base_service import TenantService

logger = logging.getLogger(__name__)


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

    def list(self, page: int = 1, per_page: int = 5, search: Optional[str] = None):
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

        total = query.count()
        items = query.offset((page - 1) * per_page).limit(per_page).all()

        return {
            "page": page,
            "per_page": per_page,
            "total": total,
            "data": items,
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
