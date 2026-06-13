from typing import List, Optional
from sqlalchemy.orm import Session
from api.models.Supplier import Supplier
from api.schemas.supplier import SupplierCreate, SupplierUpdate, SupplierBase

class SupplierService:
    def __init__(self, db: Session):
        self.db = db

    def create(self, data: SupplierCreate) -> Supplier:

#         suppliers = [
#     SupplierBase(
#         name="DistribuTech",
#         email="info@distributech.ht",
#         phone="+509 3701 5678",
#         address="Cap-Haïtien, Haïti"
#     ),
#     SupplierBase(
#         name="Global Supplies",
#         email="sales@globalsupplies.com",
#         phone="+509 3702 9101",
#         address="Jacmel, Haïti"
#     ),
#     SupplierBase(
#         name="Produits Locaux SARL",
#         email="contact@produitslocaux.ht",
#         phone="+509 3703 1122",
#         address="Gonaïves, Haïti"
#     ),
#     SupplierBase(
#         name="Techno Import",
#         email="support@technoimport.com",
#         phone="+509 3704 3344",
#         address="Les Cayes, Haïti"
#     )
# ]
#         for s in suppliers:
    # print(s.dict())
        supplier = Supplier(**data.dict())
        self.db.add(supplier)
        self.db.commit()
        self.db.refresh(supplier)
        return supplier

    def get(self, supplier_id: str) -> Optional[Supplier]:
        return self.db.query(Supplier).filter(Supplier.id == supplier_id).first()

    def list(self) -> List[Supplier]:
        return self.db.query(Supplier).all()

    def update(self, supplier_id: str, data: SupplierUpdate) -> Optional[Supplier]:
        supplier = self.get(supplier_id)
        if not supplier:
            return None
        for field, value in data.dict(exclude_unset=True).items():
            setattr(supplier, field, value)
        self.db.commit()
        self.db.refresh(supplier)
        return supplier

    def delete(self, supplier_id: str) -> bool:
        supplier = self.get(supplier_id)
        if not supplier:
            return False
        self.db.delete(supplier)
        self.db.commit()
        return True
