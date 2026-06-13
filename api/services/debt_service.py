from sqlalchemy.orm import Session
from sqlalchemy import func
from decimal import Decimal

def recalc_debt(
    db: Session,
    *,
    reference_type: str,
    reference_id: str,
):
    from api.models.Debt import Debt
    from api.models.Payment import Payment 

    debt = db.query(Debt).filter(
        Debt.reference_type == reference_type,
        Debt.reference_id == reference_id
    ).first()

    if not debt:
        return None

    paid_amount = db.query(
        func.coalesce(func.sum(Payment.amount), 0)
    ).filter(
        Payment.reference_type == reference_type,
        Payment.reference_id == reference_id
    ).scalar()

    paid_amount = Decimal(paid_amount)
    balance = Decimal(debt.total_amount) - paid_amount

    if balance <= 0:
        status = "PAID"
        balance = Decimal("0.00")
    elif paid_amount == 0:
        status = "UNPAID"
    else:
        status = "PARTIAL"

    debt.paid_amount = paid_amount
    debt.balance = balance
    debt.status = status

    db.add(debt)
    db.commit()
    db.refresh(debt)

    return debt