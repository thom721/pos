from datetime import datetime
from typing import Optional
from pydantic import BaseModel, EmailStr


class AffiliateRegister(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    phone: Optional[str] = None


class AffiliateVerifyEmail(BaseModel):
    email: EmailStr
    code: str


class AffiliateResendCode(BaseModel):
    email: EmailStr


class AffiliateLogin(BaseModel):
    email: EmailStr
    password: str


class AffiliateToken(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ReferredTenantRead(BaseModel):
    tenant_id: str
    business_name: str
    created_at: datetime
    total_earned: float


class WithdrawalRead(BaseModel):
    id: str
    amount: float
    status: str
    payout_method: Optional[str] = None
    admin_note: Optional[str] = None
    created_at: datetime
    processed_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class AffiliateDashboard(BaseModel):
    full_name: str
    email: str
    referral_code: str
    total_earned: float
    available_balance: float
    referred_tenants: list[ReferredTenantRead]
    withdrawals: list[WithdrawalRead]


class WithdrawalCreate(BaseModel):
    amount: float
    payout_method: str


class AdminWithdrawalAction(BaseModel):
    action: str  # 'approve' | 'reject' | 'mark_paid'
    note: Optional[str] = None
