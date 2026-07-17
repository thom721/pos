from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime

from api.database import get_db
from api.models.User import User
from api.models.Sale import Sale
from api.models.SaleItem import SaleItem
from api.models.Product import Product
from api.models.Warehouse import Warehouse
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/reports", tags=["Reports"])

_EXCLUDED_STATUS = "cancelled"


# ── Helpers ───────────────────────────────────────────────────────────────────

def _apply_date_filters(q, date_from, date_to):
    if date_from:
        q = q.filter(Sale.created_at >= date_from)
    if date_to:
        q = q.filter(Sale.created_at <= date_to)
    return q


def _profit_expr():
    """Margin per item = (selling_price - purchase_price) × qty."""
    return SaleItem.quantity * (
        SaleItem.unit_price - func.coalesce(Product.purchase_price, 0)
    )


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/warehouses")
def warehouse_stats(
    date_from: Optional[datetime] = Query(None),
    date_to:   Optional[datetime] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_READ)),
):
    """Agrégats CA / marge / ventes par dépôt + résumé global."""
    tid = current_user.tenant_id

    # ── Revenue & sale count per warehouse ───────────────────────────────────
    rev_q = (
        db.query(
            Sale.warehouse_id,
            func.count(Sale.id.distinct()).label("total_sales"),
            func.coalesce(func.sum(Sale.final_amount), 0).label("total_revenue"),
        )
        .filter(Sale.tenant_id == tid, Sale.status != _EXCLUDED_STATUS)
    )
    rev_q = _apply_date_filters(rev_q, date_from, date_to)
    rev_by_wh = {r.warehouse_id: r for r in rev_q.group_by(Sale.warehouse_id).all()}

    # ── Profit & items per warehouse ─────────────────────────────────────────
    profit_q = (
        db.query(
            Sale.warehouse_id,
            func.coalesce(func.sum(_profit_expr()), 0).label("total_profit"),
            func.coalesce(func.sum(SaleItem.quantity), 0).label("total_items"),
        )
        .join(SaleItem, SaleItem.sale_id == Sale.id)
        .join(Product,  Product.id == SaleItem.product_id)
        .filter(Sale.tenant_id == tid, Sale.status != _EXCLUDED_STATUS)
    )
    profit_q = _apply_date_filters(profit_q, date_from, date_to)
    profit_by_wh = {r.warehouse_id: r for r in profit_q.group_by(Sale.warehouse_id).all()}

    # ── Active warehouses ─────────────────────────────────────────────────────
    warehouses = (
        db.query(Warehouse)
        .filter(Warehouse.tenant_id == tid)
        .order_by(Warehouse.is_default.desc(), Warehouse.name)
        .all()
    )

    by_warehouse = []
    g_revenue = g_profit = g_sales = g_items = 0.0

    for wh in warehouses:
        rev_row    = rev_by_wh.get(wh.id)
        profit_row = profit_by_wh.get(wh.id)

        revenue = float(rev_row.total_revenue)    if rev_row    else 0.0
        profit  = float(profit_row.total_profit)  if profit_row else 0.0
        sales   = int(rev_row.total_sales)        if rev_row    else 0
        items   = float(profit_row.total_items)   if profit_row else 0.0
        margin  = round(profit / revenue * 100, 1) if revenue > 0 else 0.0

        g_revenue += revenue
        g_profit  += profit
        g_sales   += sales
        g_items   += items

        by_warehouse.append({
            "warehouse_id":    wh.id,
            "warehouse_name":  wh.name,
            "is_default":      wh.is_default,
            "is_active":       wh.is_active,
            "total_revenue":   revenue,
            "total_profit":    profit,
            "profit_margin":   margin,
            "total_sales":     sales,
            "total_items_sold": items,
        })

    # Sort by revenue and add rank
    by_warehouse.sort(key=lambda x: x["total_revenue"], reverse=True)
    for i, row in enumerate(by_warehouse):
        row["rank"] = i + 1

    g_margin = round(g_profit / g_revenue * 100, 1) if g_revenue > 0 else 0.0

    return {
        "global": {
            "total_revenue":    g_revenue,
            "total_profit":     g_profit,
            "profit_margin":    g_margin,
            "total_sales":      int(g_sales),
            "total_items_sold": g_items,
        },
        "by_warehouse": by_warehouse,
    }


@router.get("/top-products")
def top_products(
    date_from:    Optional[datetime] = Query(None),
    date_to:      Optional[datetime] = Query(None),
    warehouse_id: Optional[str]      = Query(None),
    limit:        int                = Query(20, le=50),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_READ)),
):
    """Top produits écoulés (quantité + CA + marge), filtrables par dépôt."""
    tid = current_user.tenant_id

    q = (
        db.query(
            Product.id.label("product_id"),
            Product.name.label("product_name"),
            func.coalesce(func.sum(SaleItem.quantity), 0).label("total_quantity"),
            func.coalesce(func.sum(SaleItem.subtotal), 0).label("total_revenue"),
            func.coalesce(func.sum(_profit_expr()), 0).label("total_profit"),
        )
        .join(SaleItem, SaleItem.product_id == Product.id)
        .join(Sale,     Sale.id == SaleItem.sale_id)
        .filter(Sale.tenant_id == tid, Sale.status != _EXCLUDED_STATUS)
    )

    q = _apply_date_filters(q, date_from, date_to)

    if warehouse_id:
        q = q.filter(Sale.warehouse_id == warehouse_id)

    rows = (
        q.group_by(Product.id, Product.name)
         .order_by(func.sum(SaleItem.subtotal).desc())
         .limit(limit)
         .all()
    )

    return [
        {
            "product_id":    r.product_id,
            "product_name":  r.product_name,
            "total_quantity": float(r.total_quantity),
            "total_revenue":  float(r.total_revenue),
            "total_profit":   float(r.total_profit),
            "profit_margin":  round(
                float(r.total_profit) / float(r.total_revenue) * 100, 1
            ) if float(r.total_revenue) > 0 else 0.0,
        }
        for r in rows
    ]
