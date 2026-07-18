from sqlalchemy.orm import Session
from fastapi import HTTPException
from api.models.Category import Category
from api.schemas.category import CategoryCreate, CategoryUpdate
from typing import List, Union
from api.services.base_service import TenantService

class CategoryService(TenantService):
    def __init__(self, db: Session, tenant_id: str | None = None):
        super().__init__(db, tenant_id)

    def create(self, data: Union[CategoryCreate, List[CategoryCreate], dict, List[dict]]):
        if not isinstance(data, list):
            data = [data]

        categories = []
        try:
            for item in data:
                payload = item if isinstance(item, dict) else item.dict()

                exists = self._q(Category).filter(Category.name == payload["name"]).first()
                if exists:
                    raise HTTPException(400, f"La catégorie « {payload['name']} » existe déjà")

                category = Category(name=payload["name"])
                self._set_tenant(category)
                self.db.add(category)
                categories.append(category)

            self.db.commit()
            for category in categories:
                self.db.refresh(category)

            return categories[0] if len(categories) == 1 else categories

        except HTTPException:
            self.db.rollback()
            raise
        except Exception as e:
            self.db.rollback()
            raise HTTPException(status_code=500, detail=str(e))


    def list(self):
        return self._q(Category).all()

    def get(self, category_id: str):
        return self._q(Category).filter(Category.id == category_id).first()

    def update(self, category_id: str, data: CategoryUpdate):
        category = self.get(category_id)
        if not category:
            return None
        for key, value in data.dict(exclude_unset=True).items():
            setattr(category, key, value)
        self.db.commit()
        self.db.refresh(category)
        return category

    def delete(self, category_id: str):
        category = self.get(category_id)
        if not category:
            return False
        self.db.delete(category)
        self.db.commit()
        return True
