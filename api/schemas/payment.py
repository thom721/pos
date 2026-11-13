from pydantic import BaseModel
from typing import Optional
from decimal import Decimal
from datetime import datetime


class PaymentUserInfo(BaseModel):
    fname: str
    lname: str

    class Config:
        from_attributes = True


class PaymentCreate(BaseModel):
    reference_type: str  # SALE ou PURCHASE
    reference_id: str
    amount: float
    method: str  # CASH, BANK, MOBILE
    # Virement bancaire / mobile money : identifiant de transaction côté
    # banque, pour la réconciliation (le reçu photo/scan se téléverse
    # séparément via POST /api/payments/{id}/receipt, une fois le paiement créé).
    bank_reference: Optional[str] = None


class PaymentReceiptUpload(BaseModel):
    """JSON (pas multipart) volontairement — un corps JSON passe par la
    meme file d'attente hors ligne generique que toute autre mutation
    (voir OfflineInterceptor/OfflineQueueService, frontend) ; un FormData
    multipart n'est pas serialisable pour une relecture differee."""
    filename: str
    content_base64: str


class PaymentResponse(BaseModel):
    id: str
    reference_type: str
    reference_id: str
    amount: Decimal
    method: str
    bank_reference: Optional[str] = None
    receipt_url: Optional[str] = None
    created_at: datetime
    user: Optional[PaymentUserInfo] = None

    class Config:
        from_attributes = True
