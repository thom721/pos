"""
Public routes — no authentication required.
Used by the Flutter Web registration/login flow and WordPress webhook.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from api.database import get_db
from api.schemas.tenant import TenantRegister, CloudLogin, CloudToken, TenantRead
from api.services.tenant_service import register_tenant, cloud_login

router = APIRouter(prefix="/api/public", tags=["Public"])


@router.post("/register", status_code=201)
def register(payload: TenantRegister, db: Session = Depends(get_db)):
    """
    Creates a new tenant + admin user.
    Called from Flutter Web registration screen or WordPress page.
    The tenant starts with status='trial' (30-day free trial).
    Payment webhooks transition status to 'active'.
    """
    tenant, user = register_tenant(
        db,
        business_name=payload.business_name,
        owner_email=payload.owner_email,
        password=payload.password,
        phone=payload.phone,
    )
    return {
        "message": "Compte créé avec succès. Période d'essai de 30 jours activée.",
        "tenant_id": tenant.id,
        "slug": tenant.slug,
        "trial_ends_at": tenant.trial_ends_at,
    }


@router.post("/login", response_model=CloudToken)
def login(payload: CloudLogin, db: Session = Depends(get_db)):
    """
    Cloud login by email + password.
    Returns JWT containing tenant_id for all subsequent requests.
    Registers the device (pos_register) on first login of a new device_id.
    """
    return cloud_login(
        db,
        email=payload.email,
        password=payload.password,
        device_id=payload.device_id,
        register_name=payload.register_name,
    )


@router.get("/tenant/{tenant_id}", response_model=TenantRead)
def get_tenant_info(tenant_id: str, db: Session = Depends(get_db)):
    """
    Returns public tenant info (used by the app to verify trial/active status).
    """
    from api.models.Tenant import Tenant
    from fastapi import HTTPException, status
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not tenant:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Tenant introuvable")
    return tenant
