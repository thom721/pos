from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime, timezone

from api.database import get_db
from api.models.User import User
from api.models.Sale import Sale
from api.models.SaleItem import SaleItem
from api.models.Product import Product
from api.models.Warehouse import Warehouse
from api.models.Category import Category
from api.models.Expense import Expense
from api.models.PayrollPeriod import PayrollPeriod
from api.models.PayrollEntry import PayrollEntry
from api.models.EmployeeLoan import EmployeeLoan
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.services import config_service

router = APIRouter(prefix="/api/reports", tags=["Reports"])

_EXCLUDED_STATUS = "CANCELLED"


# ── Helpers ───────────────────────────────────────────────────────────────────

def _apply_date_filters(q, date_from, date_to):
    if date_from:
        if date_from.tzinfo is None:
            date_from = date_from.replace(tzinfo=timezone.utc)
        q = q.filter(Sale.created_at >= date_from)
    if date_to:
        if date_to.tzinfo is None:
            date_to = date_to.replace(tzinfo=timezone.utc)
        q = q.filter(Sale.created_at <= date_to)
    return q


def _require_report_section(db: Session, tenant_id: str | None, field_name: str, label: str) -> None:
    """Les sections Dépenses/Payroll/Prêts de la page Rapports sont activables
    indépendamment par tenant (AppConfig.*_reports_enabled) — tous les
    commerces n'ont pas d'employés salariés/prêts. Vérifié ici (pas seulement
    masqué côté client) pour ne jamais exposer les données si désactivé."""
    cfg = config_service.get_or_create(db, tenant_id=tenant_id)
    if not getattr(cfg, field_name, False):
        raise HTTPException(status_code=403, detail=f"Section « {label} » désactivée dans la configuration.")


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
            func.coalesce(func.sum(Sale.discount), 0).label("total_receipt_discount"),
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
            func.coalesce(func.sum(SaleItem.discount), 0).label("total_item_discount"),
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
    g_revenue = g_profit = g_sales = g_items = g_discount = 0.0

    for wh in warehouses:
        rev_row    = rev_by_wh.get(wh.id)
        profit_row = profit_by_wh.get(wh.id)

        revenue  = float(rev_row.total_revenue)             if rev_row    else 0.0
        profit   = float(profit_row.total_profit)           if profit_row else 0.0
        sales    = int(rev_row.total_sales)                 if rev_row    else 0
        items    = float(profit_row.total_items)            if profit_row else 0.0
        discount = (
            (float(rev_row.total_receipt_discount) if rev_row else 0.0)
            + (float(profit_row.total_item_discount) if profit_row else 0.0)
        )
        margin  = round(profit / revenue * 100, 1) if revenue > 0 else 0.0

        g_revenue  += revenue
        g_profit   += profit
        g_sales    += sales
        g_items    += items
        g_discount += discount

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
            "total_discount":  discount,
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
            "total_discount":   g_discount,
        },
        "by_warehouse": by_warehouse,
    }


@router.get("/top-products")
def top_products(
    date_from:    Optional[datetime] = Query(None),
    date_to:      Optional[datetime] = Query(None),
    warehouse_id: Optional[str]      = Query(None),
    category_id:  Optional[str]      = Query(None),
    limit:        int                = Query(20, le=50),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.SALES_READ)),
):
    """Top produits écoulés (quantité + CA + marge), filtrables par dépôt et catégorie."""
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

    if category_id:
        q = q.filter(Product.category_id == category_id)

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


@router.get("/expenses")
def expenses_report(
    date_from:    Optional[datetime] = Query(None),
    date_to:      Optional[datetime] = Query(None),
    warehouse_id: Optional[str]      = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.EXPENSES_READ)),
):
    """Agrégats des dépenses — globalement, par catégorie, et par dépôt
    (sauf si warehouse_id est fourni : dans ce cas la répartition par dépôt
    n'a plus de sens, on ne renvoie que la catégorie)."""
    tid = current_user.tenant_id
    _require_report_section(db, tid, "expenses_reports_enabled", "Dépenses")

    base = db.query(Expense).filter(Expense.tenant_id == tid)
    if date_from:
        base = base.filter(Expense.expense_date >= date_from)
    if date_to:
        base = base.filter(Expense.expense_date <= date_to)
    if warehouse_id:
        base = base.filter(Expense.warehouse_id == warehouse_id)

    total_amount, count = base.with_entities(
        func.coalesce(func.sum(Expense.amount), 0), func.count(Expense.id)
    ).one()

    cat_rows = (
        base.with_entities(
            Expense.category,
            func.coalesce(func.sum(Expense.amount), 0).label("total_amount"),
            func.count(Expense.id).label("count"),
        )
        .group_by(Expense.category)
        .order_by(func.sum(Expense.amount).desc())
        .all()
    )
    by_category = [
        {"category": r.category or "Sans catégorie", "total_amount": float(r.total_amount), "count": r.count}
        for r in cat_rows
    ]

    by_warehouse = []
    if not warehouse_id:
        wh_rows = (
            base.with_entities(
                Expense.warehouse_id,
                func.coalesce(func.sum(Expense.amount), 0).label("total_amount"),
                func.count(Expense.id).label("count"),
            )
            .group_by(Expense.warehouse_id)
            .order_by(func.sum(Expense.amount).desc())
            .all()
        )
        wh_names = {w.id: w.name for w in db.query(Warehouse).filter(Warehouse.tenant_id == tid).all()}
        by_warehouse = [
            {
                "warehouse_id":   r.warehouse_id,
                "warehouse_name": wh_names.get(r.warehouse_id, "Aucun dépôt en particulier") if r.warehouse_id else "Aucun dépôt en particulier",
                "total_amount":   float(r.total_amount),
                "count":          r.count,
            }
            for r in wh_rows
        ]

    return {
        "global": {"total_amount": float(total_amount), "count": count},
        "by_category": by_category,
        "by_warehouse": by_warehouse,
    }


@router.get("/payroll")
def payroll_report(
    date_from: Optional[datetime] = Query(None),
    date_to:   Optional[datetime] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.PAYROLL_READ)),
):
    """Agrégats payroll — sommes brut/déductions/net sur les périodes dont la
    date de paie tombe dans l'intervalle, + détail par période."""
    tid = current_user.tenant_id
    _require_report_section(db, tid, "payroll_reports_enabled", "Payroll")

    # Seules les périodes "paid" représentent une dépense réelle — les
    # déductions de prêt (PayrollLoanDeduction) ne sont appliquées au solde
    # (EmployeeLoan.balance) qu'au paiement (payroll_service.pay_period), pas
    # au traitement (process_period). Une période "draft"/"processing" n'a
    # encore rien déboursé, et une période "cancelled" ne le fera jamais —
    # les deux fausseraient un rapport de dépenses réelles si comptées ici.
    q = db.query(PayrollPeriod).filter(
        PayrollPeriod.tenant_id == tid, PayrollPeriod.status == "paid",
    )
    if date_from:
        q = q.filter(PayrollPeriod.pay_date >= date_from.date())
    if date_to:
        q = q.filter(PayrollPeriod.pay_date <= date_to.date())

    periods = q.order_by(PayrollPeriod.pay_date.desc()).all()

    total_gross      = sum(float(p.total_gross) for p in periods)
    total_deductions = sum(float(p.total_deductions) for p in periods)
    total_net        = sum(float(p.total_net) for p in periods)

    employees_count = 0
    if periods:
        employees_count = db.query(func.count(func.distinct(PayrollEntry.employee_id))).filter(
            PayrollEntry.period_id.in_([p.id for p in periods])
        ).scalar() or 0

    by_period = [
        {
            "id":               p.id,
            "reference":        p.reference,
            "label":            p.label,
            "period_start":     p.period_start.isoformat(),
            "period_end":       p.period_end.isoformat(),
            "pay_date":         p.pay_date.isoformat(),
            "status":           p.status,
            "total_gross":      float(p.total_gross),
            "total_deductions": float(p.total_deductions),
            "total_net":        float(p.total_net),
        }
        for p in periods
    ]

    return {
        "global": {
            "total_gross":      total_gross,
            "total_deductions": total_deductions,
            "total_net":        total_net,
            "periods_count":    len(periods),
            "employees_count":  employees_count,
        },
        "by_period": by_period,
    }


@router.get("/loans")
def loans_report(
    date_from: Optional[datetime] = Query(None),
    date_to:   Optional[datetime] = Query(None),
    status:    Optional[str]      = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.LOANS_READ)),
):
    """Agrégats prêts/achats à crédit employés — montant total accordé, solde
    restant dû, et montant déjà remboursé (total - solde), + détail par statut."""
    tid = current_user.tenant_id
    _require_report_section(db, tid, "loans_reports_enabled", "Prêts")

    q = db.query(EmployeeLoan).filter(EmployeeLoan.tenant_id == tid)
    if date_from:
        q = q.filter(EmployeeLoan.created_at >= date_from)
    if date_to:
        q = q.filter(EmployeeLoan.created_at <= date_to)
    if status:
        q = q.filter(EmployeeLoan.status == status)

    loans = q.order_by(EmployeeLoan.created_at.desc()).all()

    total_amount  = sum(float(l.total_amount) for l in loans)
    total_balance = sum(float(l.balance) for l in loans)
    total_repaid  = total_amount - total_balance

    by_status: dict[str, dict] = {}
    for loan in loans:
        entry = by_status.setdefault(
            loan.status, {"status": loan.status, "total_amount": 0.0, "count": 0}
        )
        entry["total_amount"] += float(loan.total_amount)
        entry["count"] += 1

    return {
        "global": {
            "total_amount":  total_amount,
            "total_balance": total_balance,
            "total_repaid":  total_repaid,
            "count":         len(loans),
        },
        "by_status": list(by_status.values()),
    }
