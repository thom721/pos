from decimal import Decimal
from typing import List, Union

from sqlalchemy.orm import Session
from fastapi import HTTPException

from api.models.Discount import Discount, DiscountType, DiscountScope
from api.schemas.discount import DiscountCreate, DiscountUpdate
from api.services.base_service import TenantService
from api.core.dt_coerce import now_local


class DiscountService(TenantService):
    def __init__(self, db: Session, tenant_id: str | None = None):
        super().__init__(db, tenant_id)

    def create(self, data: Union[DiscountCreate, dict]):
        payload = data if isinstance(data, dict) else data.dict()

        exists = self._q(Discount).filter(Discount.name == payload["name"]).first()
        if exists:
            raise HTTPException(400, f"Le rabais « {payload['name']} » existe déjà")

        discount = Discount(
            name=payload["name"],
            type=DiscountType(payload["type"]),
            value=payload["value"],
            scope=DiscountScope(payload.get("scope", "both")),
            is_automatic=payload.get("is_automatic", False),
            is_active=payload.get("is_active", True),
            schedule_days=payload.get("schedule_days"),
            schedule_start=payload.get("schedule_start"),
            schedule_end=payload.get("schedule_end"),
        )
        self._set_tenant(discount)
        self.db.add(discount)
        self.db.commit()
        self.db.refresh(discount)
        return discount

    def list(self):
        return self._q(Discount).all()

    def get(self, discount_id: str):
        return self._q(Discount).filter(Discount.id == discount_id).first()

    def update(self, discount_id: str, data: DiscountUpdate):
        discount = self.get(discount_id)
        if not discount:
            return None
        for key, value in data.dict(exclude_unset=True).items():
            if key == "type" and value is not None:
                value = DiscountType(value)
            elif key == "scope" and value is not None:
                value = DiscountScope(value)
            setattr(discount, key, value)
        self.db.commit()
        self.db.refresh(discount)
        return discount

    def delete(self, discount_id: str):
        discount = self.get(discount_id)
        if not discount:
            return False
        self.db.delete(discount)
        self.db.commit()
        return True


def resolve_discount(
    db: Session,
    discount_id: str | None,
    raw_amount,
    allowed_scopes: set,
    base,
) -> tuple[Decimal, str | None]:
    """
    Si discount_id est fourni : charge le rabais catalogue, vérifie sa portée,
    et recalcule le montant côté serveur (le montant envoyé par le client est ignoré).
    Sinon : renvoie raw_amount tel quel (rabais libre — soumis à la permission
    sales.discount côté route).
    """
    if discount_id:
        discount = db.query(Discount).filter(Discount.id == str(discount_id)).first()
        if not discount:
            raise HTTPException(404, "Rabais introuvable")
        if not discount.is_active:
            raise HTTPException(400, f"Le rabais « {discount.name} » est désactivé")
        if discount.scope not in allowed_scopes:
            raise HTTPException(400, f"Le rabais « {discount.name} » n'est pas applicable ici")
        return compute_amount(discount, base), discount.id
    return Decimal(str(raw_amount or 0)), None


def compute_amount(discount: Discount, base: Decimal) -> Decimal:
    """Calcule le montant du rabais contre `base`, clampé pour ne jamais dépasser `base`."""
    base = Decimal(base or 0)
    if base <= 0:
        return Decimal(0)
    if discount.type == DiscountType.percentage:
        amount = base * Decimal(discount.value) / Decimal(100)
    else:
        amount = Decimal(discount.value)
    return min(amount, base)


def get_active_automatic_receipt_discount(db: Session, tenant_id: str | None) -> Discount | None:
    """Premier rabais automatique éligible (ticket) selon jour/heure courants, ou None."""
    now = now_local()
    weekday = str(now.weekday())
    current_time = now.time()

    query = db.query(Discount).filter(
        Discount.is_automatic == True,   # noqa: E712
        Discount.is_active == True,      # noqa: E712
        Discount.scope.in_([DiscountScope.receipt, DiscountScope.both]),
    )
    if tenant_id:
        query = query.filter(Discount.tenant_id == tenant_id)

    candidates = query.order_by(Discount.created_at).all()
    for d in candidates:
        if d.schedule_days:
            days = {x.strip() for x in d.schedule_days.split(",") if x.strip() != ""}
            if weekday not in days:
                continue
        if d.schedule_start and current_time < d.schedule_start:
            continue
        if d.schedule_end and current_time > d.schedule_end:
            continue
        return d
    return None
