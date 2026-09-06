from sqlalchemy import Column, String, Numeric, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from .base import UUIDBase
from api.core.dt_coerce import now_local


class Expense(UUIDBase):
    """Dépense d'exploitation (loyer, fournitures, transport...) — distincte
    d'un achat de stock (Purchase), qui suit ses propres lignes de produits."""
    __tablename__ = "expenses"

    tenant_id    = Column(String(36), ForeignKey('tenants.id'),    nullable=True, index=True)
    warehouse_id = Column(String(36), ForeignKey('warehouses.id'), nullable=True, index=True)
    user_id      = Column(String(36), ForeignKey('users.id'),      nullable=True, index=True)

    description = Column(String(255), nullable=False)
    category    = Column(String(100), nullable=True)
    amount      = Column(Numeric(12, 2), nullable=False)
    # Date de la dépense (reçu/facture) — distincte de created_at, qui reste
    # l'horodatage de saisie dans le système. Nommé "expense_date" (pas "date")
    # pour matcher le suffixe "_date" attendu par dt_coerce.coerce_datetimes
    # côté sync (sinon la string ISO reçue n'est jamais reconvertie en
    # datetime avant l'assignation au modèle — voir Invoice.date/Proforma.date,
    # qui ont ce problème latent).
    expense_date = Column(DateTime(timezone=False), nullable=False, default=now_local)

    warehouse = relationship("Warehouse")
    user      = relationship("User")
