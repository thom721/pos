import json
from pydantic import BaseModel, field_validator
from typing import Optional


class ClientSabotageCreate(BaseModel):
    nom: str
    prenom: str
    telephone: str
    adresse: str
    warehouse_id: Optional[str] = None
    extra_fields: Optional[dict[str, str]] = None
    # account_number n'est jamais accepté du client — toujours généré serveur.


class ClientSabotageRead(BaseModel):
    id: str
    nom: str
    prenom: str
    telephone: str
    adresse: str
    account_number: str
    warehouse_id: Optional[str] = None
    extra_fields: Optional[dict[str, str]] = None
    is_active: bool
    balance: float = 0

    @field_validator('extra_fields', mode='before')
    @classmethod
    def _parse_extra_fields(cls, v):
        if isinstance(v, str):
            try:
                return json.loads(v)
            except (json.JSONDecodeError, ValueError):
                return None
        return v

    @field_validator('balance', mode='before')
    @classmethod
    def _coerce_balance(cls, v):
        return float(v or 0)

    class Config:
        from_attributes = True


class ClientSabotageUpdate(BaseModel):
    nom: Optional[str] = None
    prenom: Optional[str] = None
    telephone: Optional[str] = None
    adresse: Optional[str] = None
    warehouse_id: Optional[str] = None
    extra_fields: Optional[dict[str, str]] = None
    is_active: Optional[bool] = None
