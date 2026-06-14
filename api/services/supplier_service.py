from typing import List, Optional
from sqlalchemy.orm import Session
from api.models.Supplier import Supplier
from api.schemas.supplier import SupplierCreate, SupplierUpdate, SupplierBase
from api.services.base_service import TenantService

class SupplierService(TenantService):
    def __init__(self, db: Session, tenant_id: str | None = None):
        super().__init__(db, tenant_id)

    def create(self, data: SupplierCreate) -> Supplier:
        supplier = Supplier(**data.dict())
        self._set_tenant(supplier)
        self.db.add(supplier)
        self.db.commit()
        self.db.refresh(supplier)
        return supplier

    def get(self, supplier_id: str) -> Optional[Supplier]:
        return self._q(Supplier).filter(Supplier.id == supplier_id).first()

    def list(self) -> List[Supplier]:
        return self._q(Supplier).all()

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
