from sqlalchemy.orm import Session
from fastapi import HTTPException
from decimal import Decimal

from api.models.Payment import Payment
from api.models.Sale import Sale
from api.models.Purchase import Purchase
from api.models.Debt import Debt


def add_payment(db: Session, data, user_id: str, tenant_id: str | None = None):
    reference_type = data.reference_type.upper()
    reference_id = str(data.reference_id)

    if reference_type == "SALE":
        entity = db.get(Sale, reference_id)
        if not entity:
            raise HTTPException(404, "Vente introuvable")
    elif reference_type == "PURCHASE":
        entity = db.get(Purchase, reference_id)
        if not entity:
            raise HTTPException(404, "Achat introuvable")
    else:
        raise HTTPException(400, "reference_type invalide (SALE ou PURCHASE)")

    amount = Decimal(str(data.amount))
    # POST /api/payments/ est le point d'entree "nouveau paiement" — jamais
    # de remboursement ici (celui-ci passe par return_service.py, qui
    # construit son Payment(amount negatif) directement, sans ce schema/
    # endpoint). Sans ce garde-fou, un montant negatif reduisait
    # silencieusement entity.paid_amount, pouvant repasser une vente deja
    # payee en partielle/impayee. SALE : 0 reste tolere (pas de cas d'usage
    # connu, mais pas de raison de le bloquer plus strictement que 0 negatif
    # ne l'etait avant). PURCHASE et tout le reste (ex: encaissement d'une
    # dette) : un paiement de 0 n'a aucun sens, rejete aussi.
    if reference_type == "SALE":
        if amount < 0:
            raise HTTPException(400, "Le montant du paiement doit être positif ou nul")
    elif amount <= 0:
        raise HTTPException(400, "Le montant du paiement doit être positif")

    payment = Payment(
        reference_type=reference_type,
        reference_id=reference_id,
        amount=amount,
        method=data.method.upper(),
        user_id=user_id
    )
    if tenant_id:
        payment.tenant_id = tenant_id
    db.add(payment)

    entity.paid_amount = (entity.paid_amount or Decimal("0")) + amount
    balance = entity.total_amount - entity.paid_amount

    if balance <= 0:
        entity.status = "PAID" if reference_type == "SALE" else "paid"
    else:
        entity.status = "PARTIAL" if reference_type == "SALE" else "partial"

    # Mise à jour de la dette correspondante
    debt = (
        db.query(Debt)
        .filter(
            Debt.reference_type == reference_type,
            Debt.reference_id == reference_id,
        )
        .first()
    )
    if debt:
        debt.paid_amount = (debt.paid_amount or Decimal("0")) + amount
        debt.balance = debt.total_amount - debt.paid_amount
        if debt.balance <= 0:
            debt.status = "PAID"
        else:
            debt.status = "PARTIAL"

    db.commit()
    db.refresh(payment)
    return payment
