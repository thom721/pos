from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import or_
import uuid

from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.core.permissions import has_permission
from api.models.User import User
from api.models.RestaurantTable import RestaurantTable
from api.models.RoomAttribute import RoomAttribute
from api.models.RestaurantOrder import RestaurantOrder, RestaurantOrderItem
from api.models.Ingredient import Ingredient
from api.models.ModifierGroup import ModifierGroup, ModifierOption
from api.models.MenuItem import MenuItem
from api.models.Product import Product
from api.services.warehouse_helper import resolve_warehouse_id
from api.ws_manager import manager

router = APIRouter(tags=["Restaurant"])


# ── Helpers ────────────────────────────────────────────────────────────────────

async def _notify(tenant_id: str):
    if tenant_id:
        await manager.notify(tenant_id)


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
        'price': float(t.price or 0),
        'price_per_day': float(t.price_per_day or 0),
        'price_per_moment': float(t.price_per_moment or 0),
        'status': t.status,
        'waiter_id': t.waiter_id,
        'waiter_name': f"{t.waiter.fname} {t.waiter.lname}".strip() if t.waiter else None,
        'created_at': t.created_at,
        'attributes': [{'key': a.key, 'value': a.value} for a in (t.attributes or [])],
    }


def _item_dict(i: RestaurantOrderItem) -> dict:
    label = getattr(i, 'label', None)
    if label:
        name = label
    elif i.menu_item_id and hasattr(i, 'menu_item') and i.menu_item:
        name = i.menu_item.name
    elif i.product:
        name = i.product.name
    else:
        name = '—'
    return {
        'id': i.id,
        'product_id': i.product_id,
        'menu_item_id': i.menu_item_id,
        'label': getattr(i, 'label', None),
        'product_name': name,
        'quantity': float(i.quantity),
        'unit_price': float(i.unit_price),
        'notes': i.notes,
        'status': i.status,
    }


def _order_dict(o: RestaurantOrder) -> dict:
    subtotal = sum(float(i.quantity) * float(i.unit_price) for i in o.items)
    tip = float(o.tip or 0)
    waiter_name = None
    if o.table and o.table.waiter:
        waiter_name = f"{o.table.waiter.fname} {o.table.waiter.lname}".strip()
    return {
        'id': o.id,
        'table_id': o.table_id,
        'table_name': o.table.name if o.table else None,
        'waiter_name': waiter_name,
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

class RoomAttrIn(BaseModel):
    key: str
    value: str

class TableCreate(BaseModel):
    name: str
    capacity: int = 4
    price: float = 0.0              # prix / nuit
    price_per_day: float = 0.0
    price_per_moment: float = 0.0
    waiter_id: Optional[str] = None
    warehouse_id: Optional[str] = None  # prioritaire sur _resolve_wh
    attributes: list[RoomAttrIn] = []

class TableUpdate(BaseModel):
    name: Optional[str] = None
    capacity: Optional[int] = None
    price: Optional[float] = None
    price_per_day: Optional[float] = None
    price_per_moment: Optional[float] = None
    status: Optional[str] = None
    waiter_id: Optional[str] = None  # '' = désassigner
    attributes: Optional[list[RoomAttrIn]] = None  # None = pas de changement

class TableAssign(BaseModel):
    waiter_id: Optional[str] = None  # None = désassigner

class OrderItemAdd(BaseModel):
    product_id: Optional[str] = None
    menu_item_id: Optional[str] = None
    quantity: float = 1.0
    notes: Optional[str] = None
    unit_price: Optional[float] = None  # override pour variante sélectionnée
    label: Optional[str] = None

class OpenOrderPayload(BaseModel):
    covers: int = 1
    notes: Optional[str] = None

class CheckoutPayload(BaseModel):
    payment_method: str = 'CASH'
    paid_amount: float
    customer_id: Optional[str] = None
    discount: float = 0.0
    tip: float = 0.0

class OrderItemUpdate(BaseModel):
    quantity: float

class IngredientCreate(BaseModel):
    name: str
    product_id: Optional[str] = None
    category_id: Optional[str] = None

class IngredientUpdate(BaseModel):
    name: Optional[str] = None
    product_id: Optional[str] = None
    category_id: Optional[str] = None

class ModifierGroupCreate(BaseModel):
    name: str
    product_id: Optional[str] = None
    menu_item_id: Optional[str] = None
    category_id: Optional[str] = None
    required: bool = False
    multi_select: bool = True

class ModifierGroupUpdate(BaseModel):
    name: Optional[str] = None
    product_id: Optional[str] = None
    menu_item_id: Optional[str] = None
    category_id: Optional[str] = None
    required: Optional[bool] = None
    multi_select: Optional[bool] = None

class ModifierOptionCreate(BaseModel):
    name: str
    extra_price: float = 0.0

class MenuItemCreate(BaseModel):
    name: str
    description: Optional[str] = None
    price: float = 0.0
    category_id: Optional[str] = None
    product_id: Optional[str] = None
    available: bool = True
    send_to_kitchen: bool = True
    variants: Optional[dict] = None
    warehouse_id: Optional[str] = None

class MenuItemUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    price: Optional[float] = None
    category_id: Optional[str] = None
    product_id: Optional[str] = None
    available: Optional[bool] = None
    send_to_kitchen: Optional[bool] = None
    variants: Optional[dict] = None
    warehouse_id: Optional[str] = None


# ── Serveurs (waiters) ────────────────────────────────────────────────────────

@router.get("/waiters/")
def list_waiters(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
):
    """Liste les utilisateurs actifs du tenant pouvant être assignés comme serveurs."""
    users = db.query(User).filter(
        User.tenant_id == current_user.tenant_id,
    ).order_by(User.fname).all()
    return [
        {'id': u.id, 'name': f"{u.fname} {u.lname}".strip(), 'username': u.username}
        for u in users
        if 'serveur' in (u.roles or [])
    ]


# ── Tables ────────────────────────────────────────────────────────────────────

@router.get("/tables/")
def list_tables(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
    warehouse_id: str | None = None,
):
    q = db.query(RestaurantTable).filter(
        RestaurantTable.tenant_id == current_user.tenant_id
    )
    if warehouse_id:
        # Le client a sélectionné un dépôt explicitement (ex: sélecteur web)
        q = q.filter(or_(
            RestaurantTable.warehouse_id == warehouse_id,
            RestaurantTable.warehouse_id.is_(None),
        ))
    elif current_user.warehouse_id:
        # L'utilisateur est restreint à des dépôts spécifiques
        wh_id = _resolve_wh(db, current_user)
        if wh_id:
            q = q.filter(or_(
                RestaurantTable.warehouse_id == wh_id,
                RestaurantTable.warehouse_id.is_(None),
            ))
    # Accès total (warehouse_id null/vide) sans filtre client → toutes les chambres
    # Un serveur (rôle 'serveur') ne voit que ses tables assignées.
    # Un cashier ou admin voit toutes les tables.
    if 'serveur' in (current_user.roles or []):
        q = q.filter(RestaurantTable.waiter_id == current_user.id)
    return [_table_dict(t) for t in q.order_by(RestaurantTable.name).all()]


@router.post("/tables/", status_code=201)
def create_table(
    data: TableCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_CREATE)),
):
    wh_id = data.warehouse_id or _resolve_wh(db, current_user)
    table = RestaurantTable(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        warehouse_id=wh_id,
        name=data.name,
        capacity=data.capacity,
        price=data.price,
        price_per_day=data.price_per_day,
        price_per_moment=data.price_per_moment,
        waiter_id=data.waiter_id or None,
    )
    db.add(table)
    db.flush()
    for attr in data.attributes:
        if attr.key.strip():
            db.add(RoomAttribute(
                id=str(uuid.uuid4()),
                tenant_id=current_user.tenant_id,
                warehouse_id=table.warehouse_id,
                table_id=table.id,
                key=attr.key.strip(),
                value=attr.value.strip(),
            ))
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
    if data.price is not None:
        table.price = data.price
    if data.price_per_day is not None:
        table.price_per_day = data.price_per_day
    if data.price_per_moment is not None:
        table.price_per_moment = data.price_per_moment
    if data.status is not None:
        table.status = data.status
    if 'waiter_id' in data.model_fields_set:
        table.waiter_id = data.waiter_id or None
    if data.attributes is not None:
        # Replace all attributes
        db.query(RoomAttribute).filter(RoomAttribute.table_id == table.id).delete()
        for attr in data.attributes:
            if attr.key.strip():
                db.add(RoomAttribute(
                    id=str(uuid.uuid4()),
                    tenant_id=current_user.tenant_id,
                    warehouse_id=table.warehouse_id,
                    table_id=table.id,
                    key=attr.key.strip(),
                    value=attr.value.strip(),
                ))
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
    warehouse_id: str | None = None,
):
    q = db.query(RestaurantOrder).filter(
        RestaurantOrder.tenant_id == current_user.tenant_id,
        RestaurantOrder.status != 'closed',
    )
    if warehouse_id:
        q = q.filter(RestaurantOrder.warehouse_id == warehouse_id)
    elif current_user.warehouse_id:
        wh_id = _resolve_wh(db, current_user)
        if wh_id:
            q = q.filter(RestaurantOrder.warehouse_id == wh_id)
    # Accès total → toutes les commandes actives du tenant
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
    payload: OpenOrderPayload,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
    table_id: Optional[str] = None,
):
    if table_id:
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
        table_id=table_id or None,
        cashier_id=current_user.id,
        covers=payload.covers,
        notes=payload.notes,
    )
    db.add(order)

    if table_id:
        table = db.query(RestaurantTable).filter(RestaurantTable.id == table_id).first()
        if table:
            table.status = 'occupied'

    db.commit()
    db.refresh(order)
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _order_dict(order)


@router.get("/orders/{order_id}")
def get_order(
    order_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
):
    order = db.query(RestaurantOrder).filter(
        RestaurantOrder.id == order_id,
        RestaurantOrder.tenant_id == current_user.tenant_id,
    ).first()
    if not order:
        raise HTTPException(404, "Commande introuvable")
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

    if not data.product_id and not data.menu_item_id and not data.label:
        raise HTTPException(400, "product_id, menu_item_id ou label requis")

    item_name: str
    item_price: float
    resolved_product_id = data.product_id
    resolved_menu_item_id = data.menu_item_id

    if data.label:
        # freeform item (room charge, etc.)
        item_name = data.label
        item_price = data.unit_price or 0
        resolved_product_id = None
        resolved_menu_item_id = None
    elif data.menu_item_id:
        mi = db.query(MenuItem).filter(
            MenuItem.id == data.menu_item_id,
            MenuItem.tenant_id == current_user.tenant_id,
        ).first()
        if not mi:
            raise HTTPException(404, "Plat introuvable")
        item_name = mi.name
        item_price = float(mi.price)
        # Résoudre le product_id depuis le MenuItem si non fourni explicitement
        if not resolved_product_id and mi.product_id:
            resolved_product_id = mi.product_id
    else:
        product = db.query(Product).filter(Product.id == data.product_id).first()
        if not product:
            raise HTTPException(404, "Produit introuvable")
        item_name = product.name
        item_price = float(product.sale_price)

    item = RestaurantOrderItem(
        id=str(uuid.uuid4()),
        order_id=order_id,
        product_id=resolved_product_id,
        menu_item_id=resolved_menu_item_id,
        unit_price=data.unit_price if data.unit_price is not None else item_price,
        quantity=data.quantity,
        notes=data.notes,
        label=data.label,
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


@router.put("/orders/{order_id}/items/{item_id}")
def update_item_quantity(
    order_id: str,
    item_id: str,
    data: OrderItemUpdate,
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
    if data.quantity <= 0:
        db.delete(item)
    else:
        item.quantity = data.quantity
    db.commit()
    order = db.query(RestaurantOrder).filter(
        RestaurantOrder.id == order_id,
        RestaurantOrder.tenant_id == current_user.tenant_id,
    ).first()
    if not order:
        raise HTTPException(404, "Commande introuvable")
    db.refresh(order)
    background_tasks.add_task(_notify, current_user.tenant_id)
    return _order_dict(order)


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
    # Only count what the register retains; excess cash is returned as change.
    collected = min(data.paid_amount, final) if data.paid_amount > 0 else 0

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
        paid_amount=collected,
        status='PAID' if data.paid_amount >= final else 'PARTIAL',
    )
    db.add(sale)
    db.flush()

    for oi in order.items:
        # Résoudre product_id et label depuis le MenuItem
        pid = oi.product_id
        item_label: str | None = None
        if oi.menu_item_id:
            mi_lookup = oi.menu_item or db.query(MenuItem).filter(MenuItem.id == oi.menu_item_id).first()
            if mi_lookup:
                item_label = mi_lookup.name
                if not pid:
                    pid = mi_lookup.product_id
        elif oi.product:
            item_label = oi.product.name
        db.add(SaleItem(
            id=str(uuid.uuid4()),
            sale_id=sale.id,
            product_id=pid,
            label=item_label,
            quantity=float(oi.quantity),
            unit_price=float(oi.unit_price),
            original_price=float(oi.unit_price),
            subtotal=float(oi.quantity) * float(oi.unit_price),
        ))

    db.add(Payment(
        reference_type='SALE',
        reference_id=sale.id,
        tenant_id=current_user.tenant_id,
        amount=collected,
        method=data.payment_method.upper() if data.payment_method else 'CASH',
        user_id=current_user.id,
    ))

    remaining = final - data.paid_amount
    if remaining > 0 and data.customer_id:
        db.add(Debt(
            reference_type='SALE',
            reference_id=sale.id,
            partner_type='CUSTOMER',
            partner_id=data.customer_id,
            tenant_id=current_user.tenant_id,
            total_amount=final,
            paid_amount=collected,
            balance=remaining,
            status='UNPAID' if data.paid_amount == 0 else 'PARTIAL',
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


# ── Ingredients ───────────────────────────────────────────────────────────────

def _ingredient_dict(i: Ingredient) -> dict:
    return {
        'id': i.id,
        'name': i.name,
        'product_id': i.product_id,
        'category_id': i.category_id,
    }


@router.get("/ingredients/")
def list_ingredients(
    product_id: Optional[str] = None,
    category_id: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
):
    """Liste les ingrédients du tenant, filtrables par produit ou catégorie."""
    q = db.query(Ingredient).filter(Ingredient.tenant_id == current_user.tenant_id)
    if product_id:
        q = q.filter(Ingredient.product_id == product_id)
    elif category_id:
        q = q.filter(Ingredient.category_id == category_id)
    return [_ingredient_dict(i) for i in q.order_by(Ingredient.name).all()]


@router.post("/ingredients/", status_code=201)
def create_ingredient(
    data: IngredientCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_CREATE)),
):
    ing = Ingredient(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        name=data.name,
        product_id=data.product_id or None,
        category_id=data.category_id or None,
    )
    db.add(ing)
    db.commit()
    db.refresh(ing)
    return _ingredient_dict(ing)


@router.put("/ingredients/{ingredient_id}")
def update_ingredient(
    ingredient_id: str,
    data: IngredientUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    ing = db.query(Ingredient).filter(
        Ingredient.id == ingredient_id,
        Ingredient.tenant_id == current_user.tenant_id,
    ).first()
    if not ing:
        raise HTTPException(404, "Ingrédient introuvable")
    if data.name is not None:
        ing.name = data.name
    if 'product_id' in data.model_fields_set:
        ing.product_id = data.product_id or None
    if 'category_id' in data.model_fields_set:
        ing.category_id = data.category_id or None
    db.commit()
    db.refresh(ing)
    return _ingredient_dict(ing)


@router.delete("/ingredients/{ingredient_id}", status_code=204)
def delete_ingredient(
    ingredient_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_DELETE)),
):
    ing = db.query(Ingredient).filter(
        Ingredient.id == ingredient_id,
        Ingredient.tenant_id == current_user.tenant_id,
    ).first()
    if not ing:
        raise HTTPException(404, "Ingrédient introuvable")
    db.delete(ing)
    db.commit()


# ── Modifier groups ───────────────────────────────────────────────────────────

def _option_dict(o: ModifierOption) -> dict:
    return {
        'id': o.id,
        'name': o.name,
        'extra_price': float(o.extra_price or 0),
    }


def _group_dict(g: ModifierGroup) -> dict:
    return {
        'id': g.id,
        'name': g.name,
        'product_id': g.product_id,
        'menu_item_id': g.menu_item_id,
        'category_id': g.category_id,
        'required': g.required,
        'multi_select': g.multi_select,
        'options': [_option_dict(o) for o in (g.options or [])],
    }


@router.get("/modifier-groups/")
def list_modifier_groups(
    product_id: Optional[str] = None,
    menu_item_id: Optional[str] = None,
    category_id: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
):
    wh_id = _resolve_wh(db, current_user)
    q = db.query(ModifierGroup).filter(
        ModifierGroup.tenant_id == current_user.tenant_id,
        or_(ModifierGroup.warehouse_id == wh_id, ModifierGroup.warehouse_id.is_(None)),
    )
    if product_id:
        q = q.filter(ModifierGroup.product_id == product_id)
    elif menu_item_id:
        q = q.filter(ModifierGroup.menu_item_id == menu_item_id)
    elif category_id:
        q = q.filter(ModifierGroup.category_id == category_id)
    return [_group_dict(g) for g in q.order_by(ModifierGroup.name).all()]


@router.post("/modifier-groups/", status_code=201)
def create_modifier_group(
    data: ModifierGroupCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_CREATE)),
):
    g = ModifierGroup(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        warehouse_id=_resolve_wh(db, current_user),
        name=data.name,
        product_id=data.product_id or None,
        menu_item_id=data.menu_item_id or None,
        category_id=data.category_id or None,
        required=data.required,
        multi_select=data.multi_select,
    )
    db.add(g)
    db.commit()
    db.refresh(g)
    return _group_dict(g)


@router.put("/modifier-groups/{group_id}")
def update_modifier_group(
    group_id: str,
    data: ModifierGroupUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    wh_id = _resolve_wh(db, current_user)
    g = db.query(ModifierGroup).filter(
        ModifierGroup.id == group_id,
        ModifierGroup.tenant_id == current_user.tenant_id,
        or_(ModifierGroup.warehouse_id == wh_id, ModifierGroup.warehouse_id.is_(None)),
    ).first()
    if not g:
        raise HTTPException(404, "Groupe introuvable")
    if data.name is not None:
        g.name = data.name
    if 'product_id' in data.model_fields_set:
        g.product_id = data.product_id or None
    if 'menu_item_id' in data.model_fields_set:
        g.menu_item_id = data.menu_item_id or None
    if 'category_id' in data.model_fields_set:
        g.category_id = data.category_id or None
    if data.required is not None:
        g.required = data.required
    if data.multi_select is not None:
        g.multi_select = data.multi_select
    db.commit()
    db.refresh(g)
    return _group_dict(g)


@router.delete("/modifier-groups/{group_id}", status_code=204)
def delete_modifier_group(
    group_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_DELETE)),
):
    wh_id = _resolve_wh(db, current_user)
    g = db.query(ModifierGroup).filter(
        ModifierGroup.id == group_id,
        ModifierGroup.tenant_id == current_user.tenant_id,
        or_(ModifierGroup.warehouse_id == wh_id, ModifierGroup.warehouse_id.is_(None)),
    ).first()
    if not g:
        raise HTTPException(404, "Groupe introuvable")
    db.delete(g)
    db.commit()


@router.post("/modifier-groups/{group_id}/options", status_code=201)
def add_modifier_option(
    group_id: str,
    data: ModifierOptionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    g = db.query(ModifierGroup).filter(
        ModifierGroup.id == group_id,
        ModifierGroup.tenant_id == current_user.tenant_id,
    ).first()
    if not g:
        raise HTTPException(404, "Groupe introuvable")
    opt = ModifierOption(
        id=str(uuid.uuid4()),
        group_id=group_id,
        name=data.name,
        extra_price=data.extra_price,
    )
    db.add(opt)
    db.commit()
    db.refresh(g)
    return _group_dict(g)


@router.delete("/modifier-groups/{group_id}/options/{option_id}", status_code=204)
def delete_modifier_option(
    group_id: str,
    option_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    opt = db.query(ModifierOption).filter(
        ModifierOption.id == option_id,
        ModifierOption.group_id == group_id,
    ).first()
    if not opt:
        raise HTTPException(404, "Option introuvable")
    db.delete(opt)
    db.commit()


# ── Menu items ────────────────────────────────────────────────────────────────

def _menu_item_dict(m: MenuItem) -> dict:
    return {
        'id': m.id,
        'name': m.name,
        'description': m.description,
        'price': float(m.price or 0),
        'category_id': m.category_id,
        'category_name': m.category.name if m.category else None,
        'product_id': m.product_id,
        'available': m.available,
        'send_to_kitchen': bool(m.send_to_kitchen) if m.send_to_kitchen is not None else True,
        'image_url': m.image_url,
        'variants': m.variants or [],
        'warehouse_id': m.warehouse_id,
    }


@router.get("/menu-items/")
def list_menu_items(
    category_id: Optional[str] = None,
    warehouse_id: Optional[str] = None,
    available_only: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_READ)),
):
    q = db.query(MenuItem).filter(MenuItem.tenant_id == current_user.tenant_id)
    if warehouse_id:
        q = q.filter(or_(MenuItem.warehouse_id == warehouse_id, MenuItem.warehouse_id.is_(None)))
    elif current_user.warehouse_id:
        wh_id = _resolve_wh(db, current_user)
        if wh_id:
            q = q.filter(or_(MenuItem.warehouse_id == wh_id, MenuItem.warehouse_id.is_(None)))
    # Accès total sans filtre → tous les plats du tenant
    if category_id:
        q = q.filter(MenuItem.category_id == category_id)
    if available_only:
        q = q.filter(MenuItem.available.is_(True))
    return [_menu_item_dict(m) for m in q.order_by(MenuItem.name).all()]


@router.post("/menu-items/", status_code=201)
def create_menu_item(
    data: MenuItemCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_CREATE)),
):
    m = MenuItem(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        warehouse_id=data.warehouse_id or _resolve_wh(db, current_user),
        name=data.name,
        description=data.description,
        price=data.price,
        category_id=data.category_id or None,
        product_id=data.product_id or None,
        available=data.available,
        send_to_kitchen=data.send_to_kitchen,
        variants=data.variants or None,
    )
    db.add(m)
    db.commit()
    db.refresh(m)
    return _menu_item_dict(m)


@router.put("/menu-items/{item_id}")
def update_menu_item(
    item_id: str,
    data: MenuItemUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_UPDATE)),
):
    m = db.query(MenuItem).filter(
        MenuItem.id == item_id,
        MenuItem.tenant_id == current_user.tenant_id,
    ).first()
    if not m:
        raise HTTPException(404, "Plat introuvable")
    if data.name is not None:
        m.name = data.name
    if data.description is not None:
        m.description = data.description
    if data.price is not None:
        m.price = data.price
    if data.category_id is not None:
        m.category_id = data.category_id or None
    if data.product_id is not None:
        m.product_id = data.product_id or None
    if data.available is not None:
        m.available = data.available
    if data.send_to_kitchen is not None:
        m.send_to_kitchen = data.send_to_kitchen
    if 'variants' in data.model_fields_set:
        m.variants = data.variants if data.variants else None
    if 'warehouse_id' in data.model_fields_set and data.warehouse_id is not None:
        m.warehouse_id = data.warehouse_id
    db.commit()
    db.refresh(m)
    return _menu_item_dict(m)


@router.delete("/menu-items/{item_id}", status_code=204)
def delete_menu_item(
    item_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.TABLES_DELETE)),
):
    wh_id = _resolve_wh(db, current_user)
    m = db.query(MenuItem).filter(
        MenuItem.id == item_id,
        MenuItem.tenant_id == current_user.tenant_id,
        or_(MenuItem.warehouse_id == wh_id, MenuItem.warehouse_id.is_(None)),
    ).first()
    if not m:
        raise HTTPException(404, "Plat introuvable")
    db.delete(m)
    db.commit()
