from sqlalchemy.orm import Session, joinedload
from fastapi import HTTPException
from api.models.PurchaseReceipt import PurchaseReceipt
from api.models.Purchase import Purchase
from api.models.PurchaseReceiptItem import PurchaseReceiptItem
from api.models.PurchaseItem import PurchaseItem
from api.models.StockMovement import StockMovement
from datetime import datetime, timezone
from sqlalchemy import func

from api.schemas.purchase_receipt import PurchaseReceiptCreate
from api.models.StockMovement import StockType
from api.services.warehouse_helper import resolve_warehouse_id

class ReceiptService:

    def __init__(self, db: Session):
        self.db = db

    def receive(self, data: PurchaseReceiptCreate, user_id: str, tenant_id: str | None = None):

        wh_id = resolve_warehouse_id(self.db, tenant_id, data.warehouse_id) if tenant_id else None
        receipt = PurchaseReceipt(
            purchase_id=data.purchase_id,
            received_by=data.received_by,
            note=data.note,
            warehouse_id=wh_id,
            tenant_id=tenant_id,
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
                purchase_receipt_id=receipt.id,
                purchase_item_id=pi.id,
                product_id=item.product_id,
                received_qty=item.received_qty,
                lot_number=item.lot_number,
                expiry_date=item.expiry_date,
            ))

            # Stock movement
            self.db.add(StockMovement(
                product_id=item.product_id,
                user_id=user_id,
                warehouse_id=wh_id,
                tenant_id=tenant_id,
                type=StockType.in_,
                quantity=item.received_qty,
                source_type="purchase_receipt",
                source_id=data.purchase_id,
                note="Entree stock (achat)",
                lot_number=item.lot_number,
                expiry_date=item.expiry_date,
            ))

        self._update_purchase_status(data.purchase_id)
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
            purchase.status = "paid"
            purchase.received_at = datetime.now(timezone.utc)
        else:
            purchase.status = "partial"

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