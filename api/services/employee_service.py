import json
from decimal import Decimal
from sqlalchemy.orm import Session
from api.models.EmployeeProfile import EmployeeProfile
from api.models.EmployeeLoan import EmployeeLoan
from api.models.LoanRepayment import LoanRepayment
from api.models.User import User
from api.schemas.employee import EmployeeProfileCreate, EmployeeProfileUpdate, EmployeeLoanCreate, LoanRepaymentCreate
from fastapi import HTTPException
import uuid
from datetime import date


# ── Employee Profile ──────────────────────────────────────────────────────────

def create_employee_profile(db: Session, data: EmployeeProfileCreate, tenant_id: str | None = None) -> EmployeeProfile:
    user = db.get(User, data.user_id)
    if not user:
        raise HTTPException(404, "Utilisateur introuvable")

    query = db.query(EmployeeProfile).filter(EmployeeProfile.user_id == data.user_id)
    if tenant_id:
        query = query.filter(EmployeeProfile.tenant_id == tenant_id)
    existing = query.first()
    if existing:
        raise HTTPException(409, "Un profil employé existe déjà pour cet utilisateur")

    profile = EmployeeProfile(**data.model_dump())
    if tenant_id:
        profile.tenant_id = tenant_id
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return _enrich_profile(profile)


def update_employee_profile(db: Session, profile_id: str, data: EmployeeProfileUpdate, tenant_id: str | None = None) -> EmployeeProfile:
    query = db.query(EmployeeProfile).filter(EmployeeProfile.id == profile_id)
    if tenant_id:
        query = query.filter(EmployeeProfile.tenant_id == tenant_id)
    profile = query.first()
    if not profile:
        raise HTTPException(404, "Profil employé introuvable")
    for k, v in data.model_dump(exclude_none=True).items():
        setattr(profile, k, v)
    db.commit()
    db.refresh(profile)
    return _enrich_profile(profile)


def get_employee_profile(db: Session, profile_id: str, tenant_id: str | None = None) -> EmployeeProfile:
    query = db.query(EmployeeProfile).filter(EmployeeProfile.id == profile_id)
    if tenant_id:
        query = query.filter(EmployeeProfile.tenant_id == tenant_id)
    profile = query.first()
    if not profile:
        raise HTTPException(404, "Profil employé introuvable")
    return _enrich_profile(profile)


def get_profile_by_user(db: Session, user_id: str, tenant_id: str | None = None) -> EmployeeProfile | None:
    query = db.query(EmployeeProfile).filter(EmployeeProfile.user_id == user_id)
    if tenant_id:
        query = query.filter(EmployeeProfile.tenant_id == tenant_id)
    profile = query.first()
    if profile:
        return _enrich_profile(profile)
    return None


def list_employee_profiles(db: Session, tenant_id: str | None = None) -> list:
    query = db.query(EmployeeProfile)
    if tenant_id:
        query = query.filter(EmployeeProfile.tenant_id == tenant_id)
    profiles = query.order_by(EmployeeProfile.created_at.desc()).all()
    return [_enrich_profile(p) for p in profiles]


def _enrich_profile(p: EmployeeProfile) -> EmployeeProfile:
    if p.user:
        p.username  = p.user.username
        p.full_name = f"{p.user.fname} {p.user.lname}".strip()
        p.phone     = p.user.phone
    return p


# ── Employee Loan ─────────────────────────────────────────────────────────────

def _loan_ref(db: Session, tenant_id: str | None = None) -> str:
    today = date.today()
    prefix = f"LOAN-{today.year}{today.month:02d}-"
    query = db.query(EmployeeLoan).filter(EmployeeLoan.reference.like(f"{prefix}%"))
    if tenant_id:
        query = query.filter(EmployeeLoan.tenant_id == tenant_id)
    count = query.count()
    return f"{prefix}{count + 1:03d}"


def create_loan(db: Session, data: EmployeeLoanCreate, created_by: str, tenant_id: str | None = None) -> EmployeeLoan:
    user = db.get(User, data.employee_id)
    if not user:
        raise HTTPException(404, "Employé introuvable")

    items_json = None
    if data.items:
        items_json = [i.model_dump(mode="json") for i in data.items]

    loan = EmployeeLoan(
        reference         = _loan_ref(db, tenant_id=tenant_id),
        employee_id       = data.employee_id,
        loan_type         = data.loan_type,
        description       = data.description,
        total_amount      = data.total_amount,
        balance           = data.total_amount,
        monthly_deduction = data.monthly_deduction,
        status            = "active",
        created_by        = created_by,
        items_json        = items_json,
    )
    if tenant_id:
        loan.tenant_id = tenant_id
    db.add(loan)
    db.commit()
    db.refresh(loan)
    return _enrich_loan(loan)


def approve_loan(db: Session, loan_id: str, approved_by: str, tenant_id: str | None = None) -> EmployeeLoan:
    query = db.query(EmployeeLoan).filter(EmployeeLoan.id == loan_id)
    if tenant_id:
        query = query.filter(EmployeeLoan.tenant_id == tenant_id)
    loan = query.first()
    if not loan:
        raise HTTPException(404, "Prêt introuvable")
    loan.approved_by = approved_by
    db.commit()
    db.refresh(loan)
    return _enrich_loan(loan)


def cancel_loan(db: Session, loan_id: str, tenant_id: str | None = None) -> EmployeeLoan:
    query = db.query(EmployeeLoan).filter(EmployeeLoan.id == loan_id)
    if tenant_id:
        query = query.filter(EmployeeLoan.tenant_id == tenant_id)
    loan = query.first()
    if not loan:
        raise HTTPException(404, "Prêt introuvable")
    if loan.status == "paid":
        raise HTTPException(400, "Prêt déjà remboursé")
    loan.status = "cancelled"
    db.commit()
    db.refresh(loan)
    return _enrich_loan(loan)


def list_loans(db: Session, employee_id: str | None = None, status: str | None = None, tenant_id: str | None = None) -> list:
    q = db.query(EmployeeLoan)
    if tenant_id:
        q = q.filter(EmployeeLoan.tenant_id == tenant_id)
    if employee_id:
        q = q.filter(EmployeeLoan.employee_id == employee_id)
    if status:
        q = q.filter(EmployeeLoan.status == status)
    loans = q.order_by(EmployeeLoan.created_at.desc()).all()
    return [_enrich_loan(l) for l in loans]


def _enrich_loan(l: EmployeeLoan) -> EmployeeLoan:
    if l.employee:
        l.employee_name = f"{l.employee.fname} {l.employee.lname}".strip()
    return l


def _get_loan(db: Session, loan_id: str, tenant_id: str | None = None) -> EmployeeLoan:
    q = db.query(EmployeeLoan).filter(EmployeeLoan.id == loan_id)
    if tenant_id:
        q = q.filter(EmployeeLoan.tenant_id == tenant_id)
    loan = q.first()
    if not loan:
        raise HTTPException(404, "Prêt introuvable")
    return loan


def repay_loan(
    db: Session,
    loan_id: str,
    data: LoanRepaymentCreate,
    created_by: str,
    tenant_id: str | None = None,
) -> EmployeeLoan:
    """Remboursement manuel — pour le cas où le payroll n'est pas utilisé
    dans le système (l'employé rembourse en espèces/mobile money directement),
    en complément de la déduction automatique appliquée au paiement d'une
    période payroll (voir payroll_service.pay_period)."""
    loan = _get_loan(db, loan_id, tenant_id)
    if loan.status != "active":
        raise HTTPException(400, f"Impossible de rembourser un prêt au statut '{loan.status}'")

    amount = Decimal(str(data.amount))
    if amount <= 0:
        raise HTTPException(400, "Le montant doit être positif")
    if amount > Decimal(str(loan.balance)):
        raise HTTPException(400, f"Le montant dépasse le solde restant ({loan.balance})")

    repayment = LoanRepayment(
        tenant_id=tenant_id, loan_id=loan.id, amount=amount,
        method=data.method, note=data.note, created_by=created_by,
    )
    db.add(repayment)

    loan.balance = Decimal(str(loan.balance)) - amount
    if loan.balance <= 0:
        loan.balance = Decimal(0)
        loan.status = "paid"

    db.commit()
    db.refresh(loan)
    return _enrich_loan(loan)


def list_repayments(db: Session, loan_id: str, tenant_id: str | None = None) -> list:
    # Vérifie l'accès au prêt (scope tenant) avant de renvoyer son historique
    _get_loan(db, loan_id, tenant_id)

    q = db.query(LoanRepayment).filter(LoanRepayment.loan_id == loan_id)
    if tenant_id:
        q = q.filter(LoanRepayment.tenant_id == tenant_id)
    repayments = q.order_by(LoanRepayment.created_at.desc()).all()
    for r in repayments:
        if r.creator:
            r.creator_name = f"{r.creator.fname} {r.creator.lname}".strip()
    return repayments
