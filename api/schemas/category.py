from pydantic import BaseModel
from typing import Optional

# ===== Category Schemas =====
class CategoryBase(BaseModel):
    name: str
    # description: Optional[str] = None

class CategoryCreate(BaseModel):
    name: str
    # description: Optional[str] = None

class CategoryRead(BaseModel):
    id: str
    name: str
    # description: Optional[str] = None

    # model_config = {
    #         "from_attributes": True
    #     }

class CategoryUpdate(BaseModel):
    name: Optional[str]
    # description: Optional[str]

class CategoryResponse(BaseModel):
    # id: str
    name: str

    class Config:
        from_attributes = True


