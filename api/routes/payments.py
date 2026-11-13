import base64
import os
import uuid

from fastapi import APIRouter, Depends, Query, BackgroundTasks, HTTPException
from api.ws_manager import manager
from sqlalchemy.orm import Session
from typing import List

from api.database import get_db
from api.models.Payment import Payment
from api.models.User import User
from api.schemas.payment import PaymentCreate, PaymentReceiptUpload, PaymentResponse
from api.services.payment_service import add_payment
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/payments", tags=["Payments"])


@router.post("/", response_model=PaymentResponse, status_code=201)
def store_payment(
    payload: PaymentCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PAYMENTS_CREATE)),
):
    result = add_payment(db, payload, current_user.id, tenant_id=current_user.tenant_id)
    background_tasks.add_task(manager.notify, current_user.tenant_id, None, ["payment", "debt"])
    return result


@router.get("/", response_model=List[PaymentResponse])
def list_payments(
    reference_type: str = Query(None, description="SALE ou PURCHASE (optionnel)"),
    reference_id: str = Query(None, description="UUID de la vente ou de l'achat (optionnel)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PAYMENTS_READ)),
):
    query = db.query(Payment)
    if reference_type:
        query = query.filter(Payment.reference_type == reference_type.upper())
    if reference_id:
        query = query.filter(Payment.reference_id == reference_id)
    if current_user.tenant_id:
        query = query.filter(Payment.tenant_id == current_user.tenant_id)
    return query.order_by(Payment.created_at.desc()).all()


_ALLOWED_RECEIPT_EXTS = {'.jpg', '.jpeg', '.png', '.webp', '.pdf'}
_RECEIPTS_DIR = "api/static/payment_receipts"
_MAX_RECEIPT_BYTES = 5 * 1024 * 1024  # 5 Mo


@router.post("/{payment_id}/receipt", response_model=PaymentResponse)
def upload_payment_receipt(
    payment_id: str,
    payload: PaymentReceiptUpload,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PAYMENTS_CREATE)),
):
    """Reçu/preuve de virement — photo ou PDF, téléversé après coup une fois
    le paiement créé (voir POST /api/payments/ pour bank_reference, le texte
    de l'identifiant de transaction, renseigné à la création). JSON+base64,
    pas multipart — voir PaymentReceiptUpload : rend cet appel rejouable par
    la file d'attente hors ligne générique du client comme n'importe quelle
    autre mutation."""
    payment = db.get(Payment, payment_id)
    if not payment or (current_user.tenant_id and payment.tenant_id != current_user.tenant_id):
        raise HTTPException(status_code=404, detail="Paiement introuvable")

    ext = os.path.splitext(payload.filename or '')[1].lower()
    if ext not in _ALLOWED_RECEIPT_EXTS:
        raise HTTPException(status_code=400, detail="Format non supporté. Utilisez jpg, png, webp ou pdf.")

    try:
        contents = base64.b64decode(payload.content_base64, validate=True)
    except Exception:
        raise HTTPException(status_code=400, detail="Contenu base64 invalide.")
    if len(contents) > _MAX_RECEIPT_BYTES:
        raise HTTPException(status_code=413, detail="Fichier trop volumineux (max 5 Mo).")

    _MAGIC = {
        b"\xff\xd8\xff": "jpg",
        b"\x89PNG":       "png",
        b"RIFF":          "webp",
        b"%PDF":          "pdf",
    }
    if not any(contents[:4].startswith(sig) for sig in _MAGIC):
        raise HTTPException(status_code=400, detail="Fichier invalide : octets magiques non reconnus.")

    if payment.receipt_url:
        old_path = os.path.join("api", payment.receipt_url.lstrip("/"))
        if os.path.exists(old_path):
            os.remove(old_path)

    os.makedirs(_RECEIPTS_DIR, exist_ok=True)
    filename = f"{uuid.uuid4()}{ext}"
    save_path = os.path.join(_RECEIPTS_DIR, filename)
    with open(save_path, "wb") as f:
        f.write(contents)

    payment.receipt_url = f"/static/payment_receipts/{filename}"
    db.commit()
    db.refresh(payment)
    return payment
