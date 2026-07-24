from sqlalchemy import ForeignKey, Column, String, Text
from sqlalchemy.orm import relationship
from .base import UUIDBase

class Supplier(UUIDBase):
    __tablename__ = "suppliers"
    tenant_id = Column(String(36), ForeignKey('tenants.id'), nullable=True, index=True)

    name = Column(String(255), nullable=False)
    phone = Column(String(50), nullable=False)
    email = Column(String(255))
    address = Column(Text, nullable=False)

    purchases = relationship("Purchase", back_populates="supplier")
     

    debts = relationship(
        "Debt",
        primaryjoin="and_(foreign(Debt.partner_id) == Supplier.id, Debt.partner_type == 'SUPPLIER')",
        foreign_keys="[Debt.partner_id]",
        viewonly=True,
    )
