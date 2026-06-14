from decimal import Decimal
from datetime import date, datetime, timezone
from sqlalchemy.orm import Session
from fastapi import HTTPException

from api.models.EmployeeProfile import EmployeeProfile
from api.models.EmployeeLoan import EmployeeLoan
from api.models.PayrollPeriod import PayrollPeriod
from api.models.PayrollEntry import PayrollEntry
from api.models.PayrollLoanDeduction import PayrollLoanDeduction
from api.schemas.payroll import PayrollPeriodCreate, PayrollEntryAdjust


# ── Reference helpers ─────────────────────────────────────────────────────────

def _period_ref(db: Session, tenant_id: str | None = None) -> str:
    today = date.today()
    prefix = f"PAY-{today.year}{today.month:02d}-"
    query = db.query(PayrollPeriod).filter(PayrollPeriod.reference.like(f"{prefix}%"))
    if tenant_id:
        query = query.filter(PayrollPeriod.tenant_id == tenant_id)
    count = query.count()
    return f"{prefix}{count + 1:03d}"


# ── CRUD ──────────────────────────────────────────────────────────────────────

def create_period(db: Session, data: PayrollPeriodCreate, created_by: str, tenant_id: str | None = None) -> PayrollPeriod:
    period = PayrollPeriod(
        reference    = _period_ref(db, tenant_id=tenant_id),
        label        = data.label,
        period_start = data.period_start,
        period_end   = data.period_end,
        pay_date     = data.pay_date,
        status       = "draft",
        notes        = data.notes,
        created_by   = created_by,
    )
    if tenant_id:
        period.tenant_id = tenant_id
    db.add(period)
    db.commit()
    db.refresh(period)
    return period


def get_period(db: Session, period_id: str, tenant_id: str | None = None) -> PayrollPeriod:
    query = db.query(PayrollPeriod).filter(PayrollPeriod.id == period_id)
    if tenant_id:
        query = query.filter(PayrollPeriod.tenant_id == tenant_id)
    period = query.first()
    if not period:
        raise HTTPException(404, "Période de paie introuvable")
    return period


def list_periods(db: Session, page: int = 1, limit: int = 20, tenant_id: str | None = None) -> dict:
    q = db.query(PayrollPeriod)
    if tenant_id:
        q = q.filter(PayrollPeriod.tenant_id == tenant_id)
    q = q.order_by(PayrollPeriod.created_at.desc())
    total = q.count()
    items = q.offset((page - 1) * limit).limit(limit).all()
    return {
        "data": items,
        "meta": {"page": page, "limit": limit, "total": total,
                 "pages": (total + limit - 1) // limit},
    }


# ── Process (compute entries from employee profiles + loans) ──────────────────

def process_period(db: Session, period_id: str, tenant_id: str | None = None) -> PayrollPeriod:
    """
    Compute a payroll period:
    1. Load all active employee profiles
    2. For each employee, compute gross salary and loan deductions
    3. Create/replace PayrollEntry + PayrollLoanDeduction rows
    4. Update period totals and set status = "processing"
    """
    period = get_period(db, period_id, tenant_id=tenant_id)
    if period.status not in ("draft", "processing"):
        raise HTTPException(400, f"Impossible de traiter une période en statut '{period.status}'")

    # Delete any existing entries for this period (re-processing)
    db.query(PayrollEntry).filter_by(period_id=period_id).delete(synchronize_session="fetch")

    query = db.query(EmployeeProfile).filter(EmployeeProfile.is_active == True)
    if tenant_id:
        query = query.filter(EmployeeProfile.tenant_id == tenant_id)
    profiles = query.all()
    if not profiles:
        raise HTTPException(400, "Aucun profil employé actif trouvé")

    total_gross = Decimal(0)
    total_deductions = Decimal(0)
    total_net = Decimal(0)

    for profile in profiles:
        base = Decimal(str(profile.base_salary))

        # Collect active loans for this employee
        loans = db.query(EmployeeLoan).filter(
            EmployeeLoan.employee_id == profile.user_id,
            EmployeeLoan.status == "active",
        ).all()

        loan_total = Decimal(0)
        loan_items = []
        for loan in loans:
            deduct = min(Decimal(str(loan.monthly_deduction)), Decimal(str(loan.balance)))
            if deduct > 0:
                loan_items.append((loan, deduct))
                loan_total += deduct

        gross   = base                         # bonuses added later via adjust
        net     = gross - loan_total           # other_deductions adjusted later

        entry = PayrollEntry(
            period_id        = period_id,
            employee_id      = profile.user_id,
            base_salary      = base,
            bonuses          = Decimal(0),
            gross_salary     = gross,
            loan_deduction   = loan_total,
            other_deductions = Decimal(0),
            net_salary       = net,
            status           = "pending",
        )
        db.add(entry)
        db.flush()  # get entry.id

        for loan, deduct in loan_items:
            db.add(PayrollLoanDeduction(
                entry_id = entry.id,
                loan_id  = loan.id,
                amount   = deduct,
            ))

        total_gross      += gross
        total_deductions += loan_total
        total_net        += net

    period.total_gross      = total_gross
    period.total_deductions = total_deductions
    period.total_net        = total_net
    period.status           = "processing"

    db.commit()
    db.refresh(period)
    return period


def adjust_entry(db: Session, entry_id: str, data: PayrollEntryAdjust, tenant_id: str | None = None) -> PayrollEntry:
    entry = db.get(PayrollEntry, entry_id)
    if not entry:
        raise HTTPException(404, "Ligne de paie introuvable")

    if data.bonuses is not None:
        entry.bonuses = data.bonuses
    if data.other_deductions is not None:
        entry.other_deductions = data.other_deductions
    if data.payment_method is not None:
        entry.payment_method = data.payment_method
    if data.notes is not None:
        entry.notes = data.notes

    # Recompute derived fields
    entry.gross_salary = entry.base_salary + entry.bonuses
    entry.net_salary   = (entry.gross_salary
                          - entry.loan_deduction
                          - entry.other_deductions)

    # Recompute period totals
    _recompute_period_totals(db, entry.period_id)

    db.commit()
    db.refresh(entry)
    return entry


def pay_period(db: Session, period_id: str, tenant_id: str | None = None) -> PayrollPeriod:
    """
    Mark all entries as paid and update loan balances.
    """
    period = get_period(db, period_id, tenant_id=tenant_id)
    if period.status != "processing":
        raise HTTPException(400, "La période doit être en statut 'processing' pour être payée")

    now = datetime.now(timezone.utc)
    entries = db.query(PayrollEntry).filter_by(period_id=period_id).all()

    for entry in entries:
        entry.status  = "paid"
        entry.paid_at = now

        # Apply loan deductions: update loan balances
        for ld in entry.loan_deductions:
            loan = db.get(EmployeeLoan, ld.loan_id)
            if loan and loan.status == "active":
                new_balance = Decimal(str(loan.balance)) - ld.amount
                loan.balance = max(Decimal(0), new_balance)
                if loan.balance <= 0:
                    loan.status = "paid"

    period.status = "paid"
    db.commit()
    db.refresh(period)
    return period


def cancel_period(db: Session, period_id: str, tenant_id: str | None = None) -> PayrollPeriod:
    period = get_period(db, period_id, tenant_id=tenant_id)
    if period.status == "paid":
        raise HTTPException(400, "Impossible d'annuler une période déjà payée")
    period.status = "cancelled"
    db.commit()
    db.refresh(period)
    return period


def get_period_detail(db: Session, period_id: str, tenant_id: str | None = None) -> dict:
    period = get_period(db, period_id, tenant_id=tenant_id)
    entries = db.query(PayrollEntry).filter_by(period_id=period_id).all()

    entries_out = []
    for e in entries:
        employee_name = None
        if e.employee:
            employee_name = f"{e.employee.fname} {e.employee.lname}".strip()

        loan_deductions = []
        for ld in e.loan_deductions:
            loan_deductions.append({
                "loan_id":   ld.loan_id,
                "amount":    str(ld.amount),
                "reference": ld.loan.reference if ld.loan else None,
            })

        entries_out.append({
            **{c.name: getattr(e, c.name)
               for c in e.__table__.columns},
            "employee_name":   employee_name,
            "loan_deductions": loan_deductions,
        })

    return {
        **{c.name: getattr(period, c.name) for c in period.__table__.columns},
        "entries": entries_out,
    }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _recompute_period_totals(db: Session, period_id: str) -> None:
    entries = db.query(PayrollEntry).filter_by(period_id=period_id).all()
    period  = db.get(PayrollPeriod, period_id)
    if not period:
        return
    period.total_gross      = sum(Decimal(str(e.gross_salary))     for e in entries)
    period.total_deductions = sum(
        Decimal(str(e.loan_deduction)) + Decimal(str(e.other_deductions))
        for e in entries
    )
    period.total_net        = sum(Decimal(str(e.net_salary))        for e in entries)
