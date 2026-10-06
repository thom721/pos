from decimal import Decimal
from typing import List

from pydantic import BaseModel, Field


class PriceTierIn(BaseModel):
    min_quantity: Decimal = Field(gt=0)  # à partir de N unités de vente
    price: Decimal = Field(gt=0)         # prix unitaire à partir de ce palier


class PriceTierRead(PriceTierIn):
    id: str


class PriceTiersSet(BaseModel):
    tiers: List[PriceTierIn]
