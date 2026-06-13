from sqlalchemy import Column, String, Text
from sqlalchemy.orm import relationship
from .base import UUIDBase

class Supplier(UUIDBase):
    __tablename__ = "suppliers"

    name = Column(String(255), nullable=False)
    phone = Column(String(50), nullable=False)
    email = Column(String(255))
    address = Column(Text, nullable=False)

    purchases = relationship("Purchase", back_populates="supplier")
     

    debts = relationship(
        "Debt",
        primaryjoin=(
            "and_("
            "foreign(Debt.reference_id) == Supplier.id, "
            "Debt.reference_type == 'SUPPLIER'"
            ")"
        ),back_populates="supplier",foreign_keys="[Debt.reference_id]", 
        viewonly=True
    )
