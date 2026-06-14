from typing import List, Optional
from sqlalchemy.orm import Session
from api.models.Customer import Customer
from api.schemas.customer import CustomerCreate, CustomerUpdate
from api.services.base_service import TenantService

class CustomerService(TenantService):
    def __init__(self, db: Session, tenant_id: str | None = None):
        super().__init__(db, tenant_id)

    def create(self, data: CustomerCreate) -> Customer:
        customer = Customer(**data.dict())
        self._set_tenant(customer)
        self.db.add(customer)
        self.db.commit()
        self.db.refresh(customer)
        return customer

    def get(self, customer_id: str) -> Optional[Customer]:
        return self._q(Customer).filter(Customer.id == customer_id).first()

    def list(self) -> List[Customer]:
        return self._q(Customer).all()

    def update(self, customer_id: str, data: CustomerUpdate) -> Optional[Customer]:
        customer = self.get(customer_id)
        if not customer:
            return None
        for field, value in data.dict(exclude_unset=True).items():
            setattr(customer, field, value)
        self.db.commit()
        self.db.refresh(customer)
        return customer

    def delete(self, customer_id: str) -> bool:
        customer = self.get(customer_id)
        if not customer:
            return False
        self.db.delete(customer)
        self.db.commit()
        return True
