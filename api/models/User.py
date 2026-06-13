# from sqlalchemy import Column, Integer, String
# # from app.database import .base
# from .base import UUIDBase

# class User(UUIDBase):
#     __tablename__ = "users"

# #     id = Column(Integer, primary_key=True)
#     name = Column(String(255))

from sqlalchemy import Column, String, JSON, Boolean
from sqlalchemy.orm import relationship
from .base import UUIDBase

class User(UUIDBase):
    __tablename__ = "users"

    fname = Column(String(255), nullable=False)
    lname = Column(String(255), nullable=False)
    username = Column(String(255), unique=True, index=True, nullable=False)
    phone = Column(String(255), unique=True, index=True, nullable=False)
    address = Column(String(255))
    email = Column(String(255), unique=True, nullable=True)

    roles = Column(JSON, nullable=True)
    permissions = Column(JSON, nullable=True)
    password = Column(String(255), nullable=False)
    must_change_password = Column(Boolean, default=True, nullable=False)

    sales            = relationship("Sale",     back_populates="user")
    purchases        = relationship("Purchase", back_populates="user")
    payments         = relationship("Payment",  back_populates="user")
    employee_profile = relationship("EmployeeProfile", back_populates="user", uselist=False)

