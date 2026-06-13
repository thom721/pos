from sqlalchemy.orm import Session
from fastapi import HTTPException
from api.models.Category import Category
from api.schemas.category import CategoryCreate, CategoryUpdate
from typing import List, Union

class CategoryService:
    def __init__(self, db: Session):
        self.db = db

    def create1(self, data: CategoryCreate):
        category = Category(**data.dict())
        self.db.add(category)
        self.db.commit()
        self.db.refresh(category)
        return category
    
    def create(self, data: Union[CategoryCreate, List[CategoryCreate], dict, List[dict]]):
        try:
            if not isinstance(data, list):
                data = [data]

            categories = []

            for item in data:
                payload = item if isinstance(item, dict) else item.dict()
                category = Category(**payload)
                self.db.add(category)
                categories.append(category)

                exists = self.db.query(Category).filter_by(name=payload["name"]).first()
                if exists:
                    print(exists)
                    # continue
                    raise HTTPException(400, f"Category {payload['name']} already exists")

            self.db.commit()

            for category in categories:
                print("---------------------data-----------------")
                self.db.refresh(category)

            return categories[0] if len(categories) == 1 else categories

        except Exception as e:
            self.db.rollback()
            raise HTTPException(status_code=500, detail=str(e))


    def list(self):
        return self.db.query(Category).all()

    def get(self, category_id: str):
        return self.db.query(Category).filter(Category.id == category_id).first()

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
