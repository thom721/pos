from sqlalchemy import Column, String, Enum as SAEnum, ForeignKey
from .base import UUIDBase


class HousekeepingTask(UUIDBase):
    __tablename__ = "housekeeping_tasks"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),          nullable=False, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'),        nullable=True,  index=True)
    table_id     = Column(String(36), ForeignKey('restaurant_tables.id'), nullable=False, index=True)
    description  = Column(String(255), nullable=False)
    status       = Column(
        SAEnum('pending', 'done', name='housekeeping_task_status'),
        default='pending',
        nullable=False,
    )
