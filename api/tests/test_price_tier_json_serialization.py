"""Bug corrigé : PriceTierIn/PriceTierRead utilisaient Decimal, que Pydantic
v2 sérialise en CHAÎNE JSON ("3.00", pas 3.00) — le client Flutter caste
min_quantity/price en `num` (price_tier_model.dart, product_repository.dart),
ce qui plantait avec "Une erreur inattendue s'est produite" dès qu'un produit
avait au moins un palier de prix enregistré. float sérialise en vrai nombre
JSON ; price_tier_service reconvertit de toute façon en Decimal avant tout
calcul (Decimal(str(...))), donc aucune perte de précision."""
import json
from decimal import Decimal

from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.schemas.price_tier import PriceTierRead


def test_price_tier_fields_serialize_as_json_numbers_not_strings():
    app = FastAPI()

    @app.get("/tiers")
    def get_tiers() -> list[PriceTierRead]:
        return [PriceTierRead(id="x", min_quantity=Decimal("3.00"), price=Decimal("1.70"))]

    client = TestClient(app)
    data = json.loads(client.get("/tiers").text)[0]

    assert isinstance(data["min_quantity"], (int, float)), \
        f"min_quantity doit être un nombre JSON, pas {type(data['min_quantity'])}"
    assert isinstance(data["price"], (int, float)), \
        f"price doit être un nombre JSON, pas {type(data['price'])}"
    assert data["min_quantity"] == 3.0
    assert data["price"] == 1.7
