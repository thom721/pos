"""Programme de parrainage — API publique (inscription/connexion affilié,
indépendante de get_current_user) + dashboard/retraits protégés par
get_current_affiliate. Voir api/core/affiliate_auth.py pour le détail de
l'isolation d'auth."""
import random
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from pwdlib import PasswordHash
from sqlalchemy import func
from sqlalchemy.orm import Session

from api.core.affiliate_auth import create_affiliate_token, get_current_affiliate
from api.core.dt_coerce import now_local
from api.database import get_db
from api.models.Affiliate import Affiliate
from api.models.AffiliateCommission import AffiliateCommission
from api.models.AffiliateWithdrawal import AffiliateWithdrawal
from api.models.PlatformConfig import PlatformConfig
from api.models.Tenant import Tenant
from api.schemas.affiliate import (
    AffiliateDashboard, AffiliateLogin, AffiliateRegister, AffiliateResendCode,
    AffiliateToken, AffiliateVerifyEmail, ReferredTenantRead, WithdrawalCreate,
    WithdrawalRead,
)
from api.services.affiliate_service import available_balance, generate_referral_code
from api.utils.email import send_affiliate_verification_email

router = APIRouter(prefix="/api/affiliate", tags=["Affiliate"])
_ph = PasswordHash.recommended()

_GENERIC_REGISTER_MESSAGE = (
    "Inscription reçue — vérifiez votre email pour le code de confirmation."
)


def _generate_code() -> str:
    return f"{random.randint(0, 999999):06d}"


def _send_verification(db: Session, affiliate: Affiliate) -> None:
    cfg = db.query(PlatformConfig).first()
    if cfg and cfg.smtp_host and cfg.smtp_from:
        send_affiliate_verification_email(
            to_addr=affiliate.email,
            code=affiliate.email_verification_code,
            smtp_host=cfg.smtp_host,
            smtp_port=cfg.smtp_port,
            smtp_user=cfg.smtp_user,
            smtp_password=cfg.smtp_password,
            smtp_from=cfg.smtp_from,
        )


@router.post("/register")
def register(body: AffiliateRegister, db: Session = Depends(get_db)):
    email = body.email.strip().lower()
    if db.query(Affiliate.id).filter(Affiliate.email == email).first():
        # Pas de message générique ici (contrairement à forgot-password) —
        # contrairement à un reset, une inscription doit dire clairement à
        # l'utilisateur que le compte existe déjà, sinon il ne peut jamais
        # se connecter ni redemander un code.
        raise HTTPException(status_code=400, detail="Un compte existe déjà avec cet email")
    if len(body.password) < 6:
        raise HTTPException(status_code=400, detail="Le mot de passe doit contenir au moins 6 caractères")

    affiliate = Affiliate(
        email=email,
        password=_ph.hash(body.password),
        full_name=body.full_name.strip(),
        phone=body.phone,
        referral_code=generate_referral_code(db),
        email_verification_code=_generate_code(),
        email_verification_expires_at=now_local() + timedelta(minutes=15),
    )
    db.add(affiliate)
    db.commit()
    _send_verification(db, affiliate)
    return {"message": _GENERIC_REGISTER_MESSAGE}


@router.post("/verify-email")
def verify_email(body: AffiliateVerifyEmail, db: Session = Depends(get_db)):
    email = body.email.strip().lower()
    affiliate = db.query(Affiliate).filter(Affiliate.email == email).first()
    if (
        not affiliate
        or not affiliate.email_verification_code
        or not affiliate.email_verification_expires_at
        or affiliate.email_verification_code != body.code.strip()
        or affiliate.email_verification_expires_at < now_local()
    ):
        raise HTTPException(status_code=400, detail="Code invalide ou expiré")

    affiliate.is_email_verified = True
    affiliate.email_verification_code = None
    affiliate.email_verification_expires_at = None
    db.commit()
    return {"message": "Email vérifié — vous pouvez vous connecter."}


@router.post("/resend-code")
def resend_code(body: AffiliateResendCode, db: Session = Depends(get_db)):
    email = body.email.strip().lower()
    affiliate = db.query(Affiliate).filter(Affiliate.email == email, Affiliate.is_email_verified == False).first()  # noqa: E712
    if affiliate:
        affiliate.email_verification_code = _generate_code()
        affiliate.email_verification_expires_at = now_local() + timedelta(minutes=15)
        db.commit()
        _send_verification(db, affiliate)
    return {"message": _GENERIC_REGISTER_MESSAGE}


@router.post("/login", response_model=AffiliateToken)
def login(body: AffiliateLogin, db: Session = Depends(get_db)):
    email = body.email.strip().lower()
    affiliate = db.query(Affiliate).filter(Affiliate.email == email).first()
    if not affiliate or not _ph.verify(body.password, affiliate.password):
        raise HTTPException(status_code=401, detail="Email ou mot de passe incorrect")
    if not affiliate.is_active:
        raise HTTPException(status_code=403, detail="Compte désactivé")
    if not affiliate.is_email_verified:
        raise HTTPException(status_code=403, detail="Email non vérifié — vérifiez votre boîte de réception")

    return AffiliateToken(access_token=create_affiliate_token(affiliate.id))


@router.get("/me/dashboard", response_model=AffiliateDashboard)
def dashboard(
    affiliate: Affiliate = Depends(get_current_affiliate),
    db: Session = Depends(get_db),
):
    rows = (
        db.query(
            Tenant.id, Tenant.business_name, Tenant.created_at,
            func.coalesce(func.sum(AffiliateCommission.commission_amount), 0),
        )
        .outerjoin(AffiliateCommission, AffiliateCommission.tenant_id == Tenant.id)
        .filter(Tenant.referred_by_affiliate_id == affiliate.id)
        .group_by(Tenant.id, Tenant.business_name, Tenant.created_at)
        .all()
    )
    referred_tenants = [
        ReferredTenantRead(
            tenant_id=r[0], business_name=r[1], created_at=r[2], total_earned=float(r[3]),
        )
        for r in rows
    ]
    total_earned = sum(t.total_earned for t in referred_tenants)

    withdrawals = (
        db.query(AffiliateWithdrawal)
        .filter(AffiliateWithdrawal.affiliate_id == affiliate.id)
        .order_by(AffiliateWithdrawal.created_at.desc())
        .all()
    )

    return AffiliateDashboard(
        full_name=affiliate.full_name,
        email=affiliate.email,
        referral_code=affiliate.referral_code,
        total_earned=total_earned,
        available_balance=float(available_balance(db, affiliate.id)),
        referred_tenants=referred_tenants,
        withdrawals=[WithdrawalRead.model_validate(w) for w in withdrawals],
    )


@router.post("/me/withdrawals", response_model=WithdrawalRead)
def request_withdrawal(
    body: WithdrawalCreate,
    affiliate: Affiliate = Depends(get_current_affiliate),
    db: Session = Depends(get_db),
):
    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="Montant invalide")
    balance = available_balance(db, affiliate.id)
    if body.amount > balance:
        raise HTTPException(status_code=400, detail=f"Solde insuffisant (disponible : {balance} HTG)")

    withdrawal = AffiliateWithdrawal(
        affiliate_id=affiliate.id,
        amount=body.amount,
        payout_method=body.payout_method,
    )
    db.add(withdrawal)
    db.commit()
    db.refresh(withdrawal)
    return WithdrawalRead.model_validate(withdrawal)
