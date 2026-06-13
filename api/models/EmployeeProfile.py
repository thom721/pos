from sqlalchemy import Column, String, Numeric, Date, Boolean, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase


class EmployeeProfile(UUIDBase):
    __tablename__ = "employee_profiles"

    user_id       = Column(String(36), ForeignKey("users.id"), unique=True, nullable=False, index=True)
    department    = Column(String(100), nullable=True)
    position      = Column(String(100), nullable=True)
    hire_date     = Column(Date, nullable=True)
    base_salary   = Column(Numeric(12, 2), nullable=False, default=0)
    # monthly / weekly / daily
    salary_type   = Column(String(20), nullable=False, default="monthly")
    is_active     = Column(Boolean, default=True, nullable=False)

    user = relationship("User", back_populates="employee_profile")
