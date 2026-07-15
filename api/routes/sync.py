"""
Sync router — two roles:

  CLOUD side  (multi-tenant server):
    POST /api/sync/token          — exchange tenant credentials for a long-lived sync token
    POST /api/sync/push           — receive bulk records from a local server
    GET  /api/sync/pull           — return records updated since a given timestamp

  LOCAL side  (local server, DB_TYPE=sqlite or local mysql):
    GET  /api/sync/status         — sync state per entity
    POST /api/sync/run            — trigger an immediate sync cycle
    POST /api/sync/configure      — save cloud URL + token to pos_server.ini
"""
import logging
from datetime import datetime, timezone, timedelta
from typing import Any

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt as _jwt
from pydantic import BaseModel
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.orm import Session

from api.core.config import settings, write_ini_config
from api.database import get_db
from api.models.Category import Category
from api.models.Customer import Customer
from api.models.Payment import Payment
from api.models.Product import Product
from api.models.Purchase import Purchase
from api.models.PurchaseItem import PurchaseItem
from api.models.ReturnRecord import ReturnRecord
from api.models.PosRegister import PosRegister
from api.models.Sale import Sale
from api.models.SaleItem import SaleItem
from api.models.Supplier import Supplier
from api.models.Tenant import Tenant
from api.models.User import User
from api.models.Debt import Debt
from api.models.Invoice import Invoice, InvoiceItem
from api.models.Proforma import Proforma, ProformaItem
from api.models.StockMovement import StockMovement
from api.models.InventoryRecord import InventoryRecord
from api.models.PurchaseReceipt import PurchaseReceipt
from api.models.PurchaseReceiptItem import PurchaseReceiptItem
from api.models.CashierSession import CashierSession
from api.models.AuditLog import AuditLog
from api.models.EmployeeProfile import EmployeeProfile
from api.models.PayrollPeriod import PayrollPeriod
from api.models.PayrollEntry import PayrollEntry
from api.models.EmployeeLoan import EmployeeLoan
from api.models.PayrollLoanDeduction import PayrollLoanDeduction

router = APIRouter(prefix="/api/sync", tags=["Sync"])
_log = logging.getLogger("pos.sync")

# ── Model registry ────────────────────────────────────────────────────────────

_MODEL_MAP: dict[str, Any] = {
    # Reference data
    "category":               Category,
    "supplier":               Supplier,
    "product":                Product,
    "customer":               Customer,
    "user":                   User,
    "pos_register":           PosRegister,
    # Sales & payments
    "sale":                   Sale,
    "sale_item":              SaleItem,
    "payment":                Payment,
    "return_record":          ReturnRecord,
    # Purchases
    "purchase":               Purchase,
    "purchase_item":          PurchaseItem,
    "purchase_receipt":       PurchaseReceipt,
    "purchase_receipt_item":  PurchaseReceiptItem,
    # Stock & inventory
    "stock_movement":         StockMovement,
    "inventory_record":       InventoryRecord,
    # Invoicing & proformas
    "invoice":                Invoice,
    "invoice_item":           InvoiceItem,
    "proforma":               Proforma,
    "proforma_item":          ProformaItem,
    # Debts
    "debt":                   Debt,
    # Cashier sessions
    "cashier_session":        CashierSession,
    # Audit trail
    "audit_log":              AuditLog,
    # HR & payroll
    "employee_profile":       EmployeeProfile,
    "payroll_period":         PayrollPeriod,
    "payroll_entry":          PayrollEntry,
    "employee_loan":          EmployeeLoan,
    "payroll_loan_deduction": PayrollLoanDeduction,
}

# ── Pydantic schemas ──────────────────────────────────────────────────────────

class SyncTokenRequest(BaseModel):
    owner_email: str
    password:    str
    device_id:   str = "default"


class PushRequest(BaseModel):
    entity_type: str
    records:     list[dict]


class SyncConfigRequest(BaseModel):
    cloud_url:   str
    owner_email: str
    password:    str
    device_id:   str = "default"


class BillingConfigRequest(BaseModel):
    billing_url: str   # URL du serveur posconnect.ht — utilisé pour le proxy licence


# ── Auth helpers ──────────────────────────────────────────────────────────────

_bearer = HTTPBearer(auto_error=False)


def _make_sync_token(tenant_id: str, device_id: str, tenant_type: str = "shared") -> str:
    payload = {
        "sub":         f"sync:{tenant_id}",
        "role":        "sync",
        "tenant_id":   tenant_id,
        "device_id":   device_id,
        "tenant_type": tenant_type,
        "exp":         datetime.utcnow() + timedelta(days=365),
    }
    return _jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def _decode_sync_token(token: str) -> dict:
    try:
        payload = _jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("role") != "sync":
            raise ValueError("not a sync token")
        return payload
    except Exception as exc:
        raise HTTPException(status_code=401, detail=f"Sync token invalide: {exc}")


def require_sync_token(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> dict:
    if not creds:
        raise HTTPException(status_code=401, detail="Token de synchronisation requis")
    return _decode_sync_token(creds.credentials)


# ── Utility ───────────────────────────────────────────────────────────────────

def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value)
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except Exception:
        return None


def _row_to_dict(row: Any) -> dict:
    d = {}
    for c in sa_inspect(type(row)).columns:
        v = getattr(row, c.key)
        if isinstance(v, datetime):
            v = v.isoformat()
        elif hasattr(v, "__float__") and not isinstance(v, (int, float, bool)):
            v = float(v)
        d[c.key] = v
    return d


# ── CLOUD: issue sync token ───────────────────────────────────────────────────

@router.post("/token")
def issue_sync_token(payload: SyncTokenRequest, db: Session = Depends(get_db)):
    """Exchange tenant owner credentials for a long-lived sync token."""
    from pwdlib import PasswordHash as _PH
    from api.models.User import User

    tenant = db.query(Tenant).filter(
        Tenant.owner_email == payload.owner_email,
        Tenant.is_local == False,  # noqa: E712
    ).first()
    if not tenant:
        raise HTTPException(status_code=404, detail="Boutique cloud introuvable pour cet email")

    user = db.query(User).filter(
        User.email == payload.owner_email,
        User.tenant_id == tenant.id,
    ).first()
    if not user or not _PH.recommended().verify(payload.password, user.password):
        raise HTTPException(status_code=403, detail="Email ou mot de passe incorrect")

    return {
        "sync_token":        _make_sync_token(tenant.id, payload.device_id, tenant.type),
        "tenant_id":         tenant.id,
        "tenant_slug":       tenant.slug,
        "business_name":     tenant.business_name,
        "tenant_type":       tenant.type,
        "self_hosted_url":   tenant.self_hosted_url or None,
        "can_manage_tenants": tenant.can_manage_tenants,
        "max_caisses":       tenant.max_caisses,
        "expires_in_days":   365,
        "user_id":           user.id,
    }


# ── CLOUD: receive push ───────────────────────────────────────────────────────

@router.post("/push")
def sync_push(
    body:   PushRequest,
    claims: dict = Depends(require_sync_token),
    db:     Session = Depends(get_db),
):
    """Local server pushes records here. Upserts each under the authenticated tenant.
    Self-hosted tenants: business data is rejected — only billing sync is allowed.
    """
    tenant_id   = claims["tenant_id"]
    tenant_type = claims.get("tenant_type", "shared")

    # Self-hosted tenants store their business data on their own server.
    # posconnect.ht only handles billing — reject any business entity push.
    if tenant_type == "selfhosted":
        raise HTTPException(
            status_code=403,
            detail="Tenant self-hosted : les données business ne se synchronisent pas sur posconnect.ht. "
                   "Utilisez votre propre serveur (self_hosted_url).",
        )

    model = _MODEL_MAP.get(body.entity_type)
    if not model:
        raise HTTPException(status_code=400, detail=f"Type d'entité inconnu: {body.entity_type}")

    col_names = {c.key for c in sa_inspect(model).columns}
    inserted = updated = skipped = 0

    for rec in body.records:
        if "tenant_id" in col_names:
            rec["tenant_id"] = tenant_id
        clean = {k: v for k, v in rec.items() if k in col_names}
        rid = clean.get("id")
        if not rid:
            skipped += 1
            continue

        existing = db.get(model, rid)
        if existing is None:
            try:
                # Savepoint so a failed INSERT only rolls back this one record,
                # not all previously inserted records in the same request.
                with db.begin_nested():
                    db.add(model(**clean))
                inserted += 1
            except Exception as exc:
                _log.warning("push insert %s %s: %s", body.entity_type, rid, exc)
                skipped += 1
        else:
            remote_ts = _parse_dt(clean.get("updated_at"))
            local_ts  = existing.updated_at
            if local_ts and local_ts.tzinfo is None:
                local_ts = local_ts.replace(tzinfo=timezone.utc)
            if remote_ts and (not local_ts or remote_ts > local_ts):
                for k, v in clean.items():
                    if k != "id":
                        setattr(existing, k, v)
                updated += 1
            else:
                skipped += 1

    db.commit()
    return {
        "ok": True, "entity_type": body.entity_type,
        "inserted": inserted, "updated": updated, "skipped": skipped,
    }


# ── CLOUD: serve pull ─────────────────────────────────────────────────────────

@router.get("/pull")
def sync_pull(
    entity_type: str = Query(...),
    since:       str = Query("1970-01-01T00:00:00+00:00"),
    claims:      dict = Depends(require_sync_token),
    db:          Session = Depends(get_db),
):
    """Return records updated since `since` for the authenticated tenant.
    Self-hosted tenants: business data pull is rejected.
    """
    tenant_id   = claims["tenant_id"]
    tenant_type = claims.get("tenant_type", "shared")

    if tenant_type == "selfhosted":
        raise HTTPException(
            status_code=403,
            detail="Tenant self-hosted : récupérez vos données depuis votre propre serveur (self_hosted_url).",
        )

    model = _MODEL_MAP.get(entity_type)
    if not model:
        raise HTTPException(status_code=400, detail=f"Type d'entité inconnu: {entity_type}")

    col_names = {c.key for c in sa_inspect(model).columns}
    since_dt  = _parse_dt(since)

    query = db.query(model)
    if "tenant_id" in col_names:
        query = query.filter(model.tenant_id == tenant_id)
    if since_dt:
        query = query.filter(model.updated_at > since_dt)

    records = [_row_to_dict(r) for r in query.limit(2000).all()]
    return {"entity_type": entity_type, "count": len(records), "records": records}


# ── LOCAL: status ─────────────────────────────────────────────────────────────

@router.get("/status")
def sync_status(db: Session = Depends(get_db)):
    from api.services.local_sync_service import get_sync_status
    return get_sync_status(db)


# ── LOCAL: trigger sync ───────────────────────────────────────────────────────

@router.post("/run")
def sync_run(db: Session = Depends(get_db)):
    from api.services.local_sync_service import run_sync
    result = run_sync(db)
    if not result.get("ok") and not result.get("pushed") and not result.get("pulled"):
        raise HTTPException(status_code=503, detail=result.get("error", "Sync échoué"))
    return result


# ── LOCAL: configure cloud connection ─────────────────────────────────────────

def _bg_run_sync():
    """Run a sync cycle in background (called after configure)."""
    try:
        from api.database import SessionLocal
        from api.services.local_sync_service import run_sync
        db = SessionLocal()
        try:
            run_sync(db)
        finally:
            db.close()
    except Exception as exc:
        _log.error("Background sync after configure error: %s", exc)


@router.post("/configure")
def sync_configure(body: SyncConfigRequest, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    """Exchange credentials with cloud, save sync token to pos_server.ini."""
    import httpx

    cloud_url = body.cloud_url.rstrip("/")
    try:
        resp = httpx.post(
            f"{cloud_url}/api/sync/token",
            json={"owner_email": body.owner_email,
                  "password":    body.password,
                  "device_id":   body.device_id},
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()
    except httpx.HTTPStatusError as exc:
        detail = exc.response.json().get("detail", str(exc))
        raise HTTPException(status_code=exc.response.status_code, detail=detail)
    except Exception as exc:
        raise HTTPException(status_code=503,
                            detail=f"Impossible de joindre le serveur cloud: {exc}")

    write_ini_config({
        "cloud_sync_url":     cloud_url,
        "cloud_sync_token":   data["sync_token"],
        "cloud_sync_enabled": "true",
        "cloud_owner_email":  body.owner_email,
        # billing_url defaults to cloud_url if not already set
        "billing_url":        cloud_url,
    })
    settings.CLOUD_SYNC_URL     = cloud_url
    settings.CLOUD_SYNC_TOKEN   = data["sync_token"]
    settings.CLOUD_SYNC_ENABLED = True
    if not settings.BILLING_URL:
        settings.BILLING_URL = cloud_url

    # Trigger immediate sync + restart periodic loop
    background_tasks.add_task(_bg_run_sync)
    try:
        from api.main import restart_auto_sync
        restart_auto_sync()
    except Exception:
        pass  # main not yet importable in tests

    return {
        "ok":            True,
        "tenant_slug":   data.get("tenant_slug"),
        "business_name": data.get("business_name"),
        "message":       "Synchronisation configurée avec succès — premier cycle lancé en arrière-plan",
    }


@router.post("/configure-billing")
def configure_billing(body: BillingConfigRequest):
    """
    Saves the billing_url (posconnect.ht) to pos_server.ini so this local
    server can proxy /api/billing/license requests to the SaaS.
    No authentication required — called by the settings screen.
    """
    billing_url = body.billing_url.rstrip("/")
    if not billing_url.startswith("http"):
        raise HTTPException(status_code=400, detail="URL invalide — doit commencer par http(s)://")

    write_ini_config({"billing_url": billing_url})
    settings.BILLING_URL = billing_url

    return {"ok": True, "billing_url": billing_url}
