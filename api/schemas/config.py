import json
from pydantic import BaseModel, field_validator
from typing import Optional


class ConfigRead(BaseModel):
    business_name: str = 'Mon Commerce'
    phone: str = ''
    email: str = ''
    address: str = ''
    logo_path: str = ''
    business_type: str = 'commerce'
    currency: str = 'HTG'
    currency_symbol: str = 'HTG '
    rate_usd: float = 130.0
    rate_eur: float = 140.0
    tax_rate: float = 0.0
    show_tax: bool = False
    receipt_footer: str = 'Merci pour votre achat !'
    pos_printer_name: str = ''
    pos_auto_print: bool = False
    doc_printer_name: str = ''
    doc_auto_print: bool = False
    hotel_checkin_fields: Optional[list] = None

    @field_validator('hotel_checkin_fields', mode='before')
    @classmethod
    def _parse_checkin(cls, v):
        if isinstance(v, str):
            try:
                return json.loads(v)
            except (json.JSONDecodeError, ValueError):
                return None
        return v

    class Config:
        from_attributes = True


class ConfigUpdate(BaseModel):
    business_name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    logo_path: Optional[str] = None
    business_type: Optional[str] = None
    currency: Optional[str] = None
    currency_symbol: Optional[str] = None
    rate_usd: Optional[float] = None
    rate_eur: Optional[float] = None
    tax_rate: Optional[float] = None
    show_tax: Optional[bool] = None
    receipt_footer: Optional[str] = None
    pos_printer_name: Optional[str] = None
    pos_auto_print: Optional[bool] = None
    doc_printer_name: Optional[str] = None
    doc_auto_print: Optional[bool] = None
    hotel_checkin_fields: Optional[list] = None
