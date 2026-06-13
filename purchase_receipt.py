Parfait 👍
Voici exactement ce que tu as demandé :
👉 les schémas (Pydantic) ET la request FastAPI pour un dashboard POS propre et professionnel.
Je vais rester simple, structuré et prêt à utiliser.
1️⃣ Schémas Pydantic (schemas/dashboard.py)
Copy code
Python
from pydantic import BaseModel
from typing import List, Dict
from datetime import date, datetime
🔹 KPIs (cartes en haut)
Copy code
Python
class DashboardKPI(BaseModel):
    today_sales: float
    today_orders: int
    today_profit: float
    average_order_value: float
🔹 Paiements
Copy code
Python
class PaymentSummary(BaseModel):
    cash: float = 0
    card: float = 0
    mobile_money: float = 0
🔹 Graphique ventes
Copy code
Python
class SalesChartItem(BaseModel):
    date: date
    total: float
🔹 Produits top vendus
Copy code
Python
class TopProduct(BaseModel):
    product_id: str
    name: str
    quantity: int
🔹 Stock faible
Copy code
Python
class LowStockProduct(BaseModel):
    product_id: str
    name: str
    quantity: int
🔹 Activité récente
Copy code
Python
class RecentActivity(BaseModel):
    type: str
    reference: str | None = None
    product: str | None = None
    quantity: int | None = None
    amount: float | None = None
    created_at: datetime
🔹 Réponse dashboard complète
Copy code
Python
class DashboardResponse(BaseModel):
    kpis: DashboardKPI
    payments_summary: PaymentSummary
    sales_chart: List[SalesChartItem]
    top_products: List[TopProduct]
    low_stock_products: List[LowStockProduct]
    recent_activity: List[RecentActivity]
2️⃣ Request FastAPI (router/dashboard.py)
Copy code
Python
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from datetime import date
from schemas.dashboard import DashboardResponse
from core.database import get_db
from core.security import get_current_user
from models.user import User

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])
🔹 Endpoint principal
Copy code
Python
@router.get("/", response_model=DashboardResponse)
def get_dashboard(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    store_id = current_user.store_id  # ou passé en paramètre

    return {
        "kpis": get_kpis(db, store_id),
        "payments_summary": get_payment_summary(db, store_id),
        "sales_chart": get_sales_chart(db, store_id),
        "top_products": get_top_products(db, store_id),
        "low_stock_products": get_low_stock_products(db, store_id),
        "recent_activity": get_recent_activity(db, store_id),
    }
3️⃣ Exemple de fonctions service (simplifié)
🔹 KPIs
Copy code
Python
def get_kpis(db: Session, store_id: str):
    today = date.today()

    today_sales = db.query(func.sum(Sale.total))\
        .filter(Sale.store_id == store_id, Sale.date == today)\
        .scalar() or 0

    today_orders = db.query(Sale)\
        .filter(Sale.store_id == store_id, Sale.date == today)\
        .count()

    today_profit = db.query(func.sum(Sale.profit))\
        .filter(Sale.store_id == store_id, Sale.date == today)\
        .scalar() or 0

    average_order_value = today_sales / today_orders if today_orders else 0

    return {
        "today_sales": today_sales,
        "today_orders": today_orders,
        "today_profit": today_profit,
        "average_order_value": average_order_value,
    }
🔹 Paiements
Copy code
Python
def get_payment_summary(db: Session, store_id: str):
    payments = (
        db.query(Payment.method, func.sum(Payment.amount))
        .filter(Payment.store_id == store_id)
        .group_by(Payment.method)
        .all()
    )

    result = {"cash": 0, "card": 0, "mobile_money": 0}
    for method, total in payments:
        result[method] = total

    return result
🔹 Activité récente
Copy code
Python
def get_recent_activity(db: Session, store_id: str):
    sales = (
        db.query(Sale)
        .filter(Sale.store_id == store_id)
        .order_by(Sale.created_at.desc())
        .limit(5)
        .all()
    )

    return [
        {
            "type": "sale",
            "reference": sale.reference,
            "amount": sale.total,
            "created_at": sale.created_at,
        }
        for sale in sales
    ]
4️⃣ Requête HTTP côté frontend
Copy code
Http
GET /api/dashboard
Authorization: Bearer <token>
Réponse JSON
Copy code
Json
{
  "kpis": { ... },
  "payments_summary": { ... },
  "sales_chart": [ ... ],
  "top_products": [ ... ],
  "low_stock_products": [ ... ],
  "recent_activity": [ ... ]
}
🧠 Bonnes pratiques POS (important)
✔ Un seul endpoint dashboard
✔ Toujours filtrer par store_id
✔ Pas de logique métier dans le frontend
✔ Cache possible (Redis)
✔ Dashboard ≠ rapports détaillés
🟢 Prochaine étape possible
Je peux maintenant :
🧮 Optimiser les requêtes SQLAlchemy
⚡ Ajouter Redis cache
📊 Préparer le frontend (Vue / React)
🔐 Ajouter permissions (admin / cashier)
👉 Dis-moi ce que tu veux faire ensuite.




Parfait 👍
Je vais te donner UNE implémentation complète et propre pour FastAPI + SQLAlchemy, exactement comme un vrai POS/ERP :
✅ Models (SQLAlchemy)
✅ Schemas (Pydantic)
✅ Services (business logic)
✅ Routes (API)
✅ Gestion livraison partielle / totale
✅ Stock movement traçable
Je vais rester clair, modulaire et production-ready.
1️⃣ MODELS (SQLAlchemy)
🔹 Purchase
Copy code
Python
class Purchase(Base):
    __tablename__ = "purchases"

    id = Column(String(36), primary_key=True)
    supplier_id = Column(String(36), nullable=False)

    status = Column(
        String(30),
        default="ordered"  # ordered | partially_received | completed | cancelled
    )

    ordered_at = Column(DateTime, default=datetime.utcnow)
    received_at = Column(DateTime, nullable=True)

    items = relationship("PurchaseItem", back_populates="purchase")
    receipts = relationship("PurchaseReceipt", back_populates="purchase")
🔹 PurchaseItem
Copy code
Python
class PurchaseItem(Base):
    __tablename__ = "purchase_items"

    id = Column(String(36), primary_key=True)
    purchase_id = Column(ForeignKey("purchases.id"))
    product_id = Column(String(36), nullable=False)

    ordered_qty = Column(Integer, nullable=False)
    unit_price = Column(Float, nullable=False)

    purchase = relationship("Purchase", back_populates="items")
🔹 PurchaseReceipt (UNE livraison)
Copy code
Python
class PurchaseReceipt(Base):
    __tablename__ = "purchase_receipts"

    id = Column(String(36), primary_key=True)
    purchase_id = Column(ForeignKey("purchases.id"))

    received_at = Column(DateTime, default=datetime.utcnow)
    received_by = Column(String(36), nullable=True)
    note = Column(Text, nullable=True)

    purchase = relationship("Purchase", back_populates="receipts")
    items = relationship("PurchaseReceiptItem", back_populates="receipt")
🔹 PurchaseReceiptItem (détails livraison)
Copy code
Python

class PurchaseReceiptItem(Base):
    __tablename__ = "purchase_receipt_items"

    id = Column(String(36), primary_key=True)
    purchase_receipt_id = Column(ForeignKey("purchase_receipts.id"))
    purchase_item_id = Column(ForeignKey("purchase_items.id"))

    product_id = Column(String(36), nullable=False)
    received_qty = Column(Integer, nullable=False)

    receipt = relationship("PurchaseReceipt", back_populates="items")
 
class StockMovement(Base):
    __tablename__ = "stock_movements"

    id = Column(String(36), primary_key=True)
    product_id = Column(String(36), nullable=False)

    quantity = Column(Integer, nullable=False)
    type = Column(String(10))  # IN / OUT

    source_type = Column(String(50))
    source_id = Column(String(36))

    created_at = Column(DateTime, default=datetime.utcnow)
2️⃣ SCHEMAS (Pydantic)
🔹 Create Purchase
Copy code
Python
class PurchaseItemCreate(BaseModel):
    product_id: str
    ordered_qty: int
    unit_price: float
Copy code
Python
class PurchaseCreate(BaseModel):
    supplier_id: str
    items: list[PurchaseItemCreate]
🔹 Receive Purchase (livraison)
Copy code
Python
class ReceiptItemCreate(BaseModel):
    purchase_item_id: str
    product_id: str
    received_qty: int
Copy code
Python
class PurchaseReceiptCreate(BaseModel):
    received_by: str | None = None
    note: str | None = None
    items: list[ReceiptItemCreate]


class PurchaseService:
    def __init__(self, db: Session):
        self.db = db

    def create_purchase(self, data: PurchaseCreate):
        purchase = Purchase(
            id=str(uuid4()),
            supplier_id=data.supplier_id
        )
        self.db.add(purchase)

        for item in data.items:
            self.db.add(PurchaseItem(
                purchase_id=purchase.id,
                product_id=item.product_id,
                ordered_qty=item.ordered_qty,
                unit_price=item.unit_price
            ))

        self.db.commit()
        return purchase


class ReceiptService:

    def __init__(self, db: Session):
        self.db = db

    def receive(self, purchase_id: str, data: PurchaseReceiptCreate):

        receipt = PurchaseReceipt(
            purchase_id=purchase_id,
            received_by=data.received_by,
            note=data.note
        )
        self.db.add(receipt)

        for item in data.items:
            pi = self.db.get(PurchaseItem, item.purchase_item_id)

            total_received = (
                self.db.query(func.coalesce(func.sum(PurchaseReceiptItem.received_qty), 0))
                .filter(PurchaseReceiptItem.purchase_item_id == pi.id)
                .scalar()
            )

            if total_received + item.received_qty > pi.ordered_qty:
                raise ValueError("Quantité reçue supérieure à la commande")

            # Receipt item
            self.db.add(PurchaseReceiptItem(
                id=str(uuid4()),
                purchase_receipt_id=receipt.id,
                purchase_item_id=pi.id,
                product_id=item.product_id,
                received_qty=item.received_qty
            ))

            # Stock movement
            self.db.add(StockMovement(
                id=str(uuid4()),
                product_id=item.product_id,
                quantity=item.received_qty,
                type="IN",
                source_type="purchase_receipt",
                source_id=receipt.id
            ))

        self._update_purchase_status(purchase_id)
        self.db.commit()

        return receipt


    def _update_purchase_status(self, purchase_id: str):
        items = self.db.query(PurchaseItem).filter_by(purchase_id=purchase_id).all()

        completed = True
        for item in items:
            received = (
                self.db.query(func.coalesce(func.sum(PurchaseReceiptItem.received_qty), 0))
                .filter(PurchaseReceiptItem.purchase_item_id == item.id)
                .scalar()
            )
            if received < item.ordered_qty:
                completed = False
                break

        purchase = self.db.get(Purchase, purchase_id)

        if completed:
            purchase.status = "completed"
            purchase.received_at = datetime.utcnow()
        else:
            purchase.status = "partially_received"


router = APIRouter(prefix="/purchases", tags=["Purchases"])

@router.post("/")
def create_purchase(
    data: PurchaseCreate,
    db: Session = Depends(get_db)
):
    return PurchaseService(db).create_purchase(data)


@router.post("/{purchase_id}/receipts")
def receive_purchase(
    purchase_id: str,
    data: PurchaseReceiptCreate,
    db: Session = Depends(get_db)
):
    return ReceiptService(db).receive(purchase_id, data)





def get_pending_items(db: Session, purchase_id: str):
    items = db.query(PurchaseItem).filter_by(purchase_id=purchase_id).all()

    result = []
    for item in items:
        received = (
            db.query(func.coalesce(func.sum(PurchaseReceiptItem.received_qty), 0))
            .filter(PurchaseReceiptItem.purchase_item_id == item.id)
            .scalar()
        )

        result.append({
            "purchase_item_id": item.id,
            "product_id": item.product_id,
            "ordered_qty": item.ordered_qty,
            "received_qty": received,
            "remaining_qty": item.ordered_qty - received,
            "unit_price": item.unit_price
        })

    return result


@router.get("/{purchase_id}/pending-items")
def pending_items(
    purchase_id: str,
    db: Session = Depends(get_db)
):
    return get_pending_items(db, purchase_id)




Parfait 👍
On passe maintenant aux SERVICES FastAPI, c’est-à-dire la vraie logique métier, sans routes pour l’instant.
Je vais te donner :
🧠 Principe des services
🔧 Service de recalcul de dette
💰 Service de création de paiement
🛒 Service vente (create sale + dette)
📦 Service achat (create purchase + dette)
⚠️ Cas limites gérés
1️⃣ Principe des services (important)
👉 Les routes appellent les services
👉 Les services parlent à la DB
👉 Les règles métier vivent ici
❌ Pas de logique dans les routes
❌ Pas de calcul dans les models
2️⃣ Service de recalcul de dette (CENTRAL)
📌 Ce service est appelé partout
Copy code
Python
from sqlalchemy.orm import Session
from sqlalchemy import func
from decimal import Decimal

def recalc_debt(
    db: Session,
    *,
    reference_type: str,
    reference_id: str,
):
    from models import Debt, Payment

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
✅ source de vérité
✅ aucun calcul ailleurs
3️⃣ Service de création de paiement
📌 TOUT paiement passe ici
Copy code
Python
def create_payment(
    db: Session,
    *,
    reference_type: str,
    reference_id: str,
    amount: Decimal,
    method: str,
    user_id: str,
):
    from models import Payment

    if amount == 0:
        raise ValueError("Payment amount cannot be zero")

    payment = Payment(
        reference_type=reference_type,
        reference_id=reference_id,
        amount=amount,
        method=method,
        user_id=user_id
    )

    db.add(payment)
    db.commit()
    db.refresh(payment)

    # recalcul automatique de la dette
    recalc_debt(
        db,
        reference_type=reference_type,
        reference_id=reference_id
    )

    return payment
✔️ paiement initial
✔️ paiement dette
✔️ remboursement (amount négatif)
4️⃣ Service création VENTE + dette
Copy code
Python
def create_sale(
    db: Session,
    *,
    customer_id: str,
    total_amount: Decimal,
):
    from models import Sale, Debt

    sale = Sale(
        customer_id=customer_id,
        total_amount=total_amount,
        status="UNPAID"
    )

    db.add(sale)
    db.commit()
    db.refresh(sale)

    debt = Debt(
        reference_type="SALE",
        reference_id=sale.id,
        partner_type="CUSTOMER",
        partner_id=customer_id,
        total_amount=total_amount,
        paid_amount=Decimal("0.00"),
        balance=total_amount,
        status="UNPAID"
    )

    db.add(debt)
    db.commit()

    return sale
📌 Le paiement n’est pas obligatoire ici
5️⃣ Service création ACHAT + dette
Copy code
Python
def create_purchase(
    db: Session,
    *,
    supplier_id: str,
    total_amount: Decimal,
):
    from models import Purchase, Debt

    purchase = Purchase(
        supplier_id=supplier_id,
        total_amount=total_amount,
        status="UNPAID"
    )

    db.add(purchase)
    db.commit()
    db.refresh(purchase)

    debt = Debt(
        reference_type="PURCHASE",
        reference_id=purchase.id,
        partner_type="SUPPLIER",
        partner_id=supplier_id,
        total_amount=total_amount,
        paid_amount=Decimal("0.00"),
        balance=total_amount,
        status="UNPAID"
    )

    db.add(debt)
    db.commit()

    return purchase
6️⃣ Cas limites gérés (IMPORTANT)
🔴 Surpaiement
autorisé → crédit
ou refusé (à décider)
👉 règle métier configurable
🔁 Remboursement
Copy code
Python
create_payment(amount = -500)
➡️ dette recalculée automatiquement
❌ Suppression paiement
INTERDITE
toujours paiement inverse
7️⃣ Flux réel (exemple)
Copy code
Text
create_sale(5000)
create_payment(2000)
create_payment(3000)
➡️ dette passe : UNPAID → PARTIAL → PAID
🧠 Résumé final
✔️ services = vérité métier
✔️ paiement = événement
✔️ dette = état recalculé
✔️ aucune logique dupliquée
🔜 Étape suivante (naturelle)
🔌 Routes FastAPI
📊 Queries dashboard
🧪 Tests métier
🔐 Permissions
👉 Dis-moi : on fait les routes FastAPI maintenant ?


