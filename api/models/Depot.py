from sqlalchemy import Column, String, Numeric, Text, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class Depot(UUIDBase):
    __tablename__ = "depots_sabotage"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),    nullable=True, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'), nullable=True, index=True)

    client_id = Column(String(36), ForeignKey('clients_sabotage.id'), nullable=False, index=True)
    user_id   = Column(String(36), ForeignKey('users.id'), nullable=True)

    amount = Column(Numeric(12, 2), nullable=False)
    note   = Column(Text, nullable=True)

    client = relationship("ClientSabotage", back_populates="depots")
