from typing import List

from pydantic import BaseModel, Field


class PriceTierIn(BaseModel):
    # float, pas Decimal : Pydantic v2 sérialise un Decimal en chaîne JSON
    # ("3.00"), que le client Flutter caste en `num` (price_tier_model.dart,
    # product_repository.dart) — un crash ("Une erreur inattendue s'est
    # produite") dès qu'un produit a au moins un palier. price_tier_service
    # reconvertit de toute façon en Decimal via Decimal(str(...)) avant tout
    # calcul, donc aucune perte de précision ici.
    min_quantity: float = Field(gt=0)  # à partir de N unités de vente
    price: float = Field(gt=0)         # prix unitaire à partir de ce palier


class PriceTierRead(PriceTierIn):
    id: str


class PriceTiersSet(BaseModel):
    tiers: List[PriceTierIn]
