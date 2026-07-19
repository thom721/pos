from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Optional
from sqlalchemy.orm import Session
import uuid

from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.core.permissions import has_permission
from api.models.User import User
from api.models.RestaurantTable import RestaurantTable
from api.models.RestaurantOrder import RestaurantOrder, RestaurantOrderItem
from api.models.Product import Product
from api.services.warehouse_helper import resolve_warehouse_id
from api.ws_manager import manager
import asyncio

router = APIRouter(tags=["Restaurant"])


# ── Helpers ────────────────────────────────────────────────────────────────────

def _notify(tenant_id: str):
    if tenant_id:
        asyncio.ensure_future(manager.notify(tenant_id))


def _is_manager(user: User) -> bool:
    roles = user.roles or []
    return 'admin' in roles or 'manager' in roles


def _resolve_wh(db: Session, user: User) -> str | None:
    """Retourne le warehouse_id à utiliser (JSON list → premier élément, sinon défaut du tenant)."""
    wh = user.warehouse_id
    if wh:
        first = wh[0] if isinstance(wh, list) else str(wh)
        if first:
            return first
    return resolve_warehouse_id(db, user.tenant_id)


def _table_dict(t: RestaurantTable) -> dict:
    return {
        'id': t.id,
        'name': t.name,
        'capacity': t.capacity,
        'status': t.status,
        'waiter_id': t.waiter_id,
        'waiter_name': f"{t.waiter.fname} {t.waiter.lname}".strip() if t.waiter else None,
        'created_at': t.created_at,
    }


def _item_dict(i: RestaurantOrderItem) -> dict:
    return {
        'id': i.id,
        'product_id': i.product_id,
        'product_name': i.product.name if i.product else None,
        'quantity': float(i.quantity),
        'unit_price': float(i.unit_price),
        'notes': i.notes,
        'status': i.status,
    }


def _order_dict(o: RestaurantOrder) -> dict:
    subtotal = sum(float(i.quantity) * float(i.unit_price) for i in o.items)
    tip = float(o.tip or 0)
    return {
        'id': o.id,
        'table_id': o.table_id,
        'table_name': o.table.name if o.table else None,
        'cashier_id': o.cashier_id,
        'covers': o.covers,
        'status': o.status,
        'notes': o.notes,
        'tip': tip,
        'sale_id': o.sale_id,
        'items': [_item_dict(i) for i in o.items],
        'subtotal': subtotal,
        'total': subtotal + tip,
        'created_at': o.created_at,
        'updated_at': o.updated_at,
    }


# ── Schemas ────────────────────────────────────────────────────────────────────

class TableCreate(BaseModel):
    name: str
    capacity: int = 4
    waiter_id: Optional[str] = None

class TableUpdate(BaseModel):
    name: Optional[str] = None
    capacity: Optional[int] = None
    status: Optional[str] = None
    waiter_id: Optional[str] = None  # '' = désassigner

class TableAssign(BaseModel):
    waiter_id: Optional[str] = None  # None = désassigner

class OrderItemAdd(BaseModel):
    product_id: str
    quantity: float = 1.0
    notes: Optional[str] = None

class OpenOrderPayload(BaseModel):
    covers: int = 1
    notes: Optional[str] = None

class CheckoutPayload(BaseModel):
    payment_method: str = 'CASH'
    paid_amount: float
    customer_id: Optional[str] = None
    discount: float = 0.0
    tip: float = 0.0


# ── Serveurs (waiters) ────────────────────────────────────────────────────────

@router.get("/waiters/")
def list_waiters(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
):
    """Liste les utilisateurs actifs du tenant pouvant être assignés comme serveurs."""
    users = db.query(User).filter(
        User.tenant_id == current_user.tenant_id,
        User.is_active == True,  # noqa: E712
    ).order_by(User.fname).all()
    return [{'id': u.id, 'name': f"{u.fname} {u.lname}".strip(), 'username': u.username} for u in users]


# ── Tables ────────────────────────────────────────────────────────────────────

@router.get("/tables/")
def list_tables(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
):
    wh_id = _resolve_wh(db, current_user)
    q = db.query(RestaurantTable).filter(
        RestaurantTable.tenant_id == current_user.tenant_id
    )
    if wh_id:
        q = q.filter(RestaurantTable.warehouse_id == wh_id)
    # Un serveur (cashier) ne voit que ses tables assignées
    if not _is_manager(current_user):
        q = q.filter(RestaurantTable.waiter_id == current_user.id)
    return [_table_dict(t) for t in q.order_by(RestaurantTable.name).all()]


@router.post("/tables/", status_code=201)
def create_table(
    data: TableCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_CREATE)),
):
    table = RestaurantTable(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        warehouse_id=_resolve_wh(db, current_user),
        name=data.name,
        capacity=data.capacity,
        waiter_id=data.waiter_id or None,
    )
    db.add(table)
    db.commit()
    db.refresh(table)
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _table_dict(table)


@router.put("/tables/{table_id}")
def update_table(
    table_id: str,
    data: TableUpdate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    table = db.query(RestaurantTable).filter(
        RestaurantTable.id == table_id,
        RestaurantTable.tenant_id == current_user.tenant_id,
    ).first()
    if not table:
        raise HTTPException(404, "Table introuvable")
    if data.name is not None:
        table.name = data.name
    if data.capacity is not None:
        table.capacity = data.capacity
    if data.status is not None:
        table.status = data.status
    if 'waiter_id' in data.model_fields_set:
        table.waiter_id = data.waiter_id or None
    db.commit()
    db.refresh(table)
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _table_dict(table)


@router.put("/tables/{table_id}/assign")
def assign_waiter(
    table_id: str,
    data: TableAssign,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    """Assigne (ou désassigne) un serveur à une table."""
    if not _is_manager(current_user):
        raise HTTPException(403, "Seul un manager peut assigner les serveurs")
    table = db.query(RestaurantTable).filter(
        RestaurantTable.id == table_id,
        RestaurantTable.tenant_id == current_user.tenant_id,
    ).first()
    if not table:
        raise HTTPException(404, "Table introuvable")
    table.waiter_id = data.waiter_id or None
    db.commit()
    db.refresh(table)
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _table_dict(table)


@router.delete("/tables/{table_id}", status_code=204)
def delete_table(
    table_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_DELETE)),
):
    table = db.query(RestaurantTable).filter(
        RestaurantTable.id == table_id,
        RestaurantTable.tenant_id == current_user.tenant_id,
    ).first()
    if not table:
        raise HTTPException(404, "Table introuvable")
    open_order = db.query(RestaurantOrder).filter(
        RestaurantOrder.table_id == table_id,
        RestaurantOrder.status != 'closed',
    ).first()
    if open_order:
        raise HTTPException(400, "Impossible de supprimer une table avec une commande en cours")
    db.delete(table)
    db.commit()


# ── Orders ────────────────────────────────────────────────────────────────────

@router.get("/orders/")
def list_orders(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
):
    q = db.query(RestaurantOrder).filter(
        RestaurantOrder.tenant_id == current_user.tenant_id,
        RestaurantOrder.status != 'closed',
    )
    return [_order_dict(o) for o in q.all()]


@router.get("/orders/table/{table_id}")
def get_table_order(
    table_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
):
    order = db.query(RestaurantOrder).filter(
        RestaurantOrder.table_id == table_id,
        RestaurantOrder.tenant_id == current_user.tenant_id,
        RestaurantOrder.status != 'closed',
    ).first()
    if not order:
        return None
    return _order_dict(order)


@router.post("/orders/", status_code=201)
def create_order(
    table_id: str,
    payload: OpenOrderPayload,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    existing = db.query(RestaurantOrder).filter(
        RestaurantOrder.table_id == table_id,
        RestaurantOrder.status != 'closed',
    ).first()
    if existing:
        return _order_dict(existing)

    order = RestaurantOrder(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        warehouse_id=_resolve_wh(db, current_user),
        table_id=table_id,
        cashier_id=current_user.id,
        covers=payload.covers,
        notes=payload.notes,
    )
    db.add(order)

    table = db.query(RestaurantTable).filter(RestaurantTable.id == table_id).first()
    if table:
        table.status = 'occupied'

    db.commit()
    db.refresh(order)
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _order_dict(order)


@router.post("/orders/{order_id}/items", status_code=201)
def add_item(
    order_id: str,
    data: OrderItemAdd,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    order = db.query(RestaurantOrder).filter(
        RestaurantOrder.id == order_id,
        RestaurantOrder.tenant_id == current_user.tenant_id,
    ).first()
    if not order:
        raise HTTPException(404, "Commande introuvable")
    if order.status == 'closed':
        raise HTTPException(400, "Cette commande est déjà clôturée")

    product = db.query(Product).filter(Product.id == data.product_id).first()
    if not product:
        raise HTTPException(404, "Produit introuvable")

    item = RestaurantOrderItem(
        id=str(uuid.uuid4()),
        order_id=order_id,
        product_id=data.product_id,
        quantity=data.quantity,
        unit_price=product.sale_price,
        notes=data.notes,
    )
    db.add(item)
    db.commit()
    db.refresh(order)
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _order_dict(order)


@router.delete("/orders/{order_id}/items/{item_id}", status_code=204)
def remove_item(
    order_id: str,
    item_id: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    item = db.query(RestaurantOrderItem).filter(
        RestaurantOrderItem.id == item_id,
        RestaurantOrderItem.order_id == order_id,
    ).first()
    if not item:
        raise HTTPException(404, "Article introuvable")
    db.delete(item)
    db.commit()
    background_tasks.add_task(_notify, current_user.tenant_id)


@router.put("/orders/{order_id}/kitchen")
def send_to_kitchen(
    order_id: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    order = db.query(RestaurantOrder).filter(
        RestaurantOrder.id == order_id,
        RestaurantOrder.tenant_id == current_user.tenant_id,
    ).first()
    if not order:
        raise HTTPException(404, "Commande introuvable")
    if not order.items:
        raise HTTPException(400, "Aucun article dans la commande")
    order.status = 'sent_to_kitchen'
    db.commit()
    db.refresh(order)
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _order_dict(order)


@router.put("/orders/{order_id}/ready")
def mark_ready(
    order_id: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    order = db.query(RestaurantOrder).filter(
        RestaurantOrder.id == order_id,
        RestaurantOrder.tenant_id == current_user.tenant_id,
    ).first()
    if not order:
        raise HTTPException(404, "Commande introuvable")
    order.status = 'ready'
    db.commit()
    db.refresh(order)
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _order_dict(order)


@router.post("/orders/{order_id}/checkout")
def checkout_order(
    order_id: str,
    data: CheckoutPayload,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_CREATE)),
):
    from api.models.Sale import Sale
    from api.models.SaleItem import SaleItem
    from api.models.Payment import Payment
    from api.models.Debt import Debt
    import random

    order = db.query(RestaurantOrder).filter(
        RestaurantOrder.id == order_id,
        RestaurantOrder.tenant_id == current_user.tenant_id,
    ).first()
    if not order:
        raise HTTPException(404, "Commande introuvable")
    if order.status == 'closed':
        raise HTTPException(400, "Cette commande est déjà clôturée")
    if not order.items:
        raise HTTPException(400, "Aucun article à encaisser")

    subtotal = sum(float(i.quantity) * float(i.unit_price) for i in order.items)
    tip = max(0.0, data.tip)
    discount = min(data.discount, subtotal)
    final = subtotal - discount + tip

    reference = f"VNT-{random.randint(1000000000, 9999999999)}"
    sale = Sale(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        warehouse_id=order.warehouse_id,
        user_id=current_user.id,
        customer_id=data.customer_id,
        reference=reference,
        total_amount=subtotal,
        discount=discount,
        final_amount=final,
        paid_amount=data.paid_amount,
        status='PAID' if data.paid_amount >= final else 'PARTIAL',
    )
    db.add(sale)
    db.flush()

    for oi in order.items:
        db.add(SaleItem(
            id=str(uuid.uuid4()),
            sale_id=sale.id,
            product_id=oi.product_id,
            quantity=float(oi.quantity),
            unit_price=float(oi.unit_price),
            original_price=float(oi.unit_price),
            subtotal=float(oi.quantity) * float(oi.unit_price),
        ))

    db.add(Payment(
        id=str(uuid.uuid4()),
        sale_id=sale.id,
        tenant_id=current_user.tenant_id,
        amount=data.paid_amount,
        method=data.payment_method,
    ))

    remaining = final - data.paid_amount
    if remaining > 0 and data.customer_id:
        debt = db.query(Debt).filter(
            Debt.customer_id == data.customer_id,
            Debt.tenant_id == current_user.tenant_id,
        ).first()
        if debt:
            debt.balance = float(debt.balance) + remaining
        else:
            db.add(Debt(
                id=str(uuid.uuid4()),
                tenant_id=current_user.tenant_id,
                customer_id=data.customer_id,
                balance=remaining,
            ))

    # Enregistrer le pourboire sur la commande
    order.tip = tip
    order.status = 'closed'
    order.sale_id = sale.id

    table = db.query(RestaurantTable).filter(RestaurantTable.id == order.table_id).first()
    if table:
        table.status = 'free'

    db.commit()
    background_tasks.add_task(_notify, current_user.tenant_id)
    return {
        'sale_id': sale.id,
        'reference': reference,
        'subtotal': subtotal,
        'discount': discount,
        'tip': tip,
        'total': final,
        'paid': data.paid_amount,
        'change': max(0.0, data.paid_amount - final),
        'covers': order.covers,
        'table_name': table.name if table else None,
    }
