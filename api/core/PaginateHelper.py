from pydantic import BaseModel
from typing import List, Generic, TypeVar 
T = TypeVar("T")
class PaginatedResponse(BaseModel, Generic[T]):
    page: int
    per_page: int
    total: int
    data: List[T]