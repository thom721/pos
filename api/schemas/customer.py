from pydantic import BaseModel, EmailStr
from typing import Optional


class CustomerBase(BaseModel):
    name: str
    fname: Optional[str] = ''
    nif: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    credit_limit: Optional[float] = 0


class CustomerCreate(CustomerBase):
    # UUID généré côté client pour l'offline-first (voir SaleCreate.client_id)
    # — utilisé comme id du client créé, pour que la vente faite dans la
    # foulée (qui référence cet id immédiatement, avant toute synchro) reste
    # valide même si la création du client ne synchronise que plus tard.
    client_id: Optional[str] = None
    # true = l'utilisateur a déjà confirmé vouloir créer un doublon (nom déjà
    # existant) — voir CustomerService.create. Toujours true pour un item
    # rejoué depuis la file hors-ligne (aucune confirmation interactive
    # possible en arrière-plan).
    confirm_duplicate: bool = False


class CustomerRead(CustomerBase):
    id: str
    credit_limit: float = 0
    # Lecture seule — géré uniquement par sale_service (jamais accepté en
    # entrée sur CustomerCreate/CustomerUpdate).
    loyalty_balance: float = 0
    full_name: str = ''

    model_config = {"from_attributes": True}


class CustomerUpdate(BaseModel):
    name: Optional[str] = None
    fname: Optional[str] = None
    nif: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    credit_limit: Optional[float] = None
