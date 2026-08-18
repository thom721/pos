from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from datetime import datetime, timezone, timedelta
from math import ceil
from typing import Callable, List

from pydantic import BaseModel

from api.database import get_db
from api.models.User import User
from api.models.Tenant import Tenant
from api.models.BillingPayment import BillingPayment
from api.models.PlatformConfig import PlatformConfig
from api.models.Warehouse import Warehouse
from api.models.PosRegister import PosRegister
from api.core.config import settings
from api.core.billing_crypto import try_decrypt_date, encrypt_date
from api.core.dt_coerce import now_local
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.services import billing_extra_service as _billing


class SubmitPaymentRequest(BaseModel):
    method: str = "manual"        # moncash | natcash | manual
    months: int = 1               # 1–12 (ignoré si plan_type='annual')
    reference: str | None = None  # preuve de transaction optionnelle
    plan_type: str = "monthly"    # 'monthly' | 'annual'


class SubmitRegisterPaymentRequest(BaseModel):
    """Paiement pour une ou plusieurs caisses spécifiques (par warehouse)."""
    register_ids: list[str]        # UUIDs de PosRegister à payer
    method: str = "manual"
    months: int = 1                # ignoré si plan_type='annual'
    reference: str | None = None
    plan_type: str = "monthly"


class SubmitEntrepotPaymentRequest(BaseModel):
    """Paiement pour un ou plusieurs entrepôts spécifiques."""
    entrepot_ids: list[str]        # UUIDs de Warehouse (is_entrepot=True) à payer
    method: str = "manual"
    months: int = 1                # ignoré si plan_type='annual'
    reference: str | None = None
    plan_type: str = "monthly"

router = APIRouter(prefix="/api/billing", tags=["Billing"])


# "Après la première année (1 an ou 12 mois)" — voir clarification utilisateur :
# s'applique uniformément à toute caisse/tout entrepôt (initial ou supplémentaire),
# indépendamment d'un statut affilié.
_RENEWAL_PERIOD_DAYS = 365


def _renewal_pricing(started_at, now, normal_price: float, renewal_price: float):
    """Prix applicable pour LE PROCHAIN renouvellement de cette ressource
    (caisse ou entrepôt), et la date à partir de laquelle le prix de
    renouvellement s'applique. `started_at` absent (jamais démarré) → prix
    normal, pas de date de bascule."""
    if not started_at:
        return normal_price, None
    effective_at = started_at + timedelta(days=_RENEWAL_PERIOD_DAYS)
    applicable = renewal_price if now >= effective_at else normal_price
    return applicable, effective_at


def _get_tenant(db: Session, user: User) -> Tenant:
    if not user.tenant_id:
        raise HTTPException(status_code=400, detail="Compte local — pas d'abonnement cloud")
    tenant = db.query(Tenant).filter(Tenant.id == user.tenant_id).first()
    if not tenant or tenant.is_local:
        raise HTTPException(status_code=400, detail="Pas de tenant cloud associé")
    return tenant


def _compute_plan_usage(tenant: Tenant, db: Session, cfg: PlatformConfig | None) -> dict:
    """Calcule le détail d'utilisation du plan.

    Modèle : 1 caisse initiale par dépôt est incluse. Seules les caisses
    supplémentaires (is_initial=False) sont facturées.
    """
    now = now_local()

    # Toutes les caisses actives
    caisse_count = db.query(PosRegister).filter(
        PosRegister.tenant_id == tenant.id,
        PosRegister.is_active == True,  # noqa: E712
    ).count()

    # Caisses initiales — 1 par dépôt, incluses dans le plan
    initial_count = db.query(PosRegister).filter(
        PosRegister.tenant_id == tenant.id,
        PosRegister.is_active == True,  # noqa: E712
        PosRegister.is_initial == True,  # noqa: E712
    ).count()

    # Fallback: si aucune caisse n'est marquée is_initial (données antérieures à la colonne),
    # on considère que 1 caisse est incluse dans le plan — évite faux surcoût.
    if initial_count == 0 and caisse_count > 0:
        initial_count = 1

    extra_caisse_count = max(0, caisse_count - initial_count)

    # Dépôts = warehouses actifs (illimités, sans surcharge). L'entrepôt
    # central n'est pas un dépôt de vente — exclu du décompte facturé.
    depot_count = db.query(Warehouse).filter(
        Warehouse.tenant_id == tenant.id,
        Warehouse.is_active == True,  # noqa: E712
        Warehouse.is_entrepot == False,  # noqa: E712
    ).count()

    # Toutes les caisses (initiales et supplémentaires) sont facturées au même
    # prix — sauf celles ayant dépassé leur première année d'abonnement, qui
    # basculent sur le prix de renouvellement (voir _renewal_pricing).
    xc_htg = float(cfg.price_per_extra_caisse_htg) if cfg else 500.0
    xc_usd = float(cfg.price_per_extra_caisse_usd) if cfg else 4.0
    rc_htg = float(cfg.renewal_price_per_caisse_htg) if cfg else xc_htg
    rc_usd = float(cfg.renewal_price_per_caisse_usd) if cfg else xc_usd

    # Détail par caisse avec warehouse pour affichage dans la page abonnement.
    # Chaque caisse (initiale ou non) a ses propres dates de facturation.
    regs_q = (
        db.query(PosRegister, Warehouse)
        .outerjoin(Warehouse, PosRegister.warehouse_id == Warehouse.id)
        .filter(
            PosRegister.tenant_id == tenant.id,
            PosRegister.is_active == True,  # noqa: E712
        )
        .all()
    )

    total_htg = 0.0
    total_usd = 0.0
    registers_detail = []
    for reg, wh in regs_q:
        sub_end   = reg.subscription_ends_at
        trial_end = reg.trial_ends_at

        if sub_end and sub_end > now:
            reg_status = "active"
        elif trial_end and trial_end > now:
            reg_status = "trial"
        elif sub_end or trial_end:
            reg_status = "expired"
        else:
            reg_status = "no_subscription"

        sub_started = getattr(reg, "subscription_started_at", None)
        unit_htg, renewal_at = _renewal_pricing(sub_started, now, xc_htg, rc_htg)
        unit_usd, _          = _renewal_pricing(sub_started, now, xc_usd, rc_usd)
        total_htg += unit_htg
        total_usd += unit_usd
        registers_detail.append({
            "id":                      reg.id,
            "name":                    reg.name,
            "warehouse_name":          wh.name if wh else None,
            "is_initial":              bool(reg.is_initial),
            "trial_ends_at":           reg.trial_ends_at.isoformat()           if reg.trial_ends_at           else None,
            "subscription_started_at": sub_started.isoformat()                 if sub_started                 else None,
            "subscription_ends_at":    reg.subscription_ends_at.isoformat()    if reg.subscription_ends_at    else None,
            "monthly_htg":             unit_htg,
            "monthly_usd":             unit_usd,
            "renewal_price_htg":       rc_htg,
            "renewal_price_usd":       rc_usd,
            "renewal_effective_at":    renewal_at.isoformat() if renewal_at else None,
            "status":                  reg_status,
        })

    # Entrepôts — pas d'essai gratuit (contrairement aux caisses), prix
    # réutilisé de price_per_extra_depot_htg/usd (jusqu'ici jamais branché).
    # Pas de subscription_started_at sur Warehouse — created_at sert d'ancre
    # pour la première année (voir clarification utilisateur).
    xd_htg = float(cfg.price_per_extra_depot_htg) if cfg else 500.0
    xd_usd = float(cfg.price_per_extra_depot_usd) if cfg else 4.0
    rd_htg = float(cfg.renewal_price_per_depot_htg) if cfg else xd_htg
    rd_usd = float(cfg.renewal_price_per_depot_usd) if cfg else xd_usd
    entrepots_q = db.query(Warehouse).filter(
        Warehouse.tenant_id == tenant.id,
        Warehouse.is_entrepot == True,  # noqa: E712
    ).all()

    entrepots_detail = []
    for wh in entrepots_q:
        sub_end = wh.subscription_ends_at
        ent_status = "active" if sub_end and sub_end > now else "unpaid"
        unit_htg, renewal_at = _renewal_pricing(wh.created_at, now, xd_htg, rd_htg)
        unit_usd, _          = _renewal_pricing(wh.created_at, now, xd_usd, rd_usd)
        entrepots_detail.append({
            "id":                   wh.id,
            "name":                 wh.name,
            "address":              wh.address,
            "subscription_ends_at": sub_end.isoformat() if sub_end else None,
            "monthly_htg":          unit_htg,
            "monthly_usd":          unit_usd,
            "renewal_price_htg":    rd_htg,
            "renewal_price_usd":    rd_usd,
            "renewal_effective_at": renewal_at.isoformat() if renewal_at else None,
            "status":               ent_status,
        })

    return {
        "current_caisses":            caisse_count,
        "extra_caisses":              extra_caisse_count,
        "extra_depots":               0,
        "max_caisses":                initial_count,
        "current_depots":             depot_count,
        "price_per_caisse_htg":       xc_htg,
        "price_per_caisse_usd":       xc_usd,
        "price_per_extra_caisse_htg": xc_htg,
        "price_per_extra_caisse_usd": xc_usd,
        "renewal_price_per_caisse_htg": rc_htg,
        "renewal_price_per_caisse_usd": rc_usd,
        "total_monthly_htg":          total_htg,
        "total_monthly_usd":          total_usd,
        "registers":                  registers_detail,
        "price_per_entrepot_htg":     xd_htg,
        "price_per_entrepot_usd":     xd_usd,
        "renewal_price_per_depot_htg": rd_htg,
        "renewal_price_per_depot_usd": rd_usd,
        "entrepots":                  entrepots_detail,
    }


@router.get("/config")
def get_billing_config(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Returns platform payment config visible to tenants (numbers, prices, modes)."""
    cfg = db.query(PlatformConfig).first()
    if not cfg:
        return {
            "moncash_number": "", "natcash_number": "",
            "monthly_price_htg": 1500.0, "monthly_price_usd": 12.0,
            "moncash_mode": "manual", "natcash_mode": "manual",
            "support_email": "", "support_whatsapp": "",
            "price_per_extra_caisse_htg": 500.0, "price_per_extra_caisse_usd": 4.0,
            "price_per_extra_depot_htg":  500.0, "price_per_extra_depot_usd":  4.0,
            "renewal_price_per_caisse_htg": 500.0, "renewal_price_per_caisse_usd": 4.0,
            "renewal_price_per_depot_htg":  500.0, "renewal_price_per_depot_usd":  4.0,
            "entrepot_trial_days": 30, "entrepot_trial_all": False,
        }
    return {
        "moncash_number":    cfg.moncash_number,
        "natcash_number":    cfg.natcash_number,
        "monthly_price_htg": float(cfg.monthly_price_htg),
        "monthly_price_usd": float(cfg.monthly_price_usd),
        "moncash_mode":      cfg.moncash_mode or "manual",
        "natcash_mode":      cfg.natcash_mode or "manual",
        "support_email":     cfg.support_email,
        "support_whatsapp":  cfg.support_whatsapp,
        "price_per_extra_caisse_htg": float(cfg.price_per_extra_caisse_htg),
        "price_per_extra_caisse_usd": float(cfg.price_per_extra_caisse_usd),
        "price_per_extra_depot_htg":  float(getattr(cfg, "price_per_extra_depot_htg", 500.0)),
        "price_per_extra_depot_usd":  float(getattr(cfg, "price_per_extra_depot_usd", 4.0)),
        "renewal_price_per_caisse_htg": float(getattr(cfg, "renewal_price_per_caisse_htg", 500.0)),
        "renewal_price_per_caisse_usd": float(getattr(cfg, "renewal_price_per_caisse_usd", 4.0)),
        "renewal_price_per_depot_htg":  float(getattr(cfg, "renewal_price_per_depot_htg", 500.0)),
        "renewal_price_per_depot_usd":  float(getattr(cfg, "renewal_price_per_depot_usd", 4.0)),
        "annual_discount_pct": int(getattr(cfg, "annual_discount_pct", 20)),
        # Méthodes de paiement activées
        "cash_enabled":    bool(getattr(cfg, "cash_enabled",    True)),
        "moncash_enabled": bool(getattr(cfg, "moncash_enabled", True)),
        "natcash_enabled": bool(getattr(cfg, "natcash_enabled", True)),
        "card_enabled":    bool(getattr(cfg, "card_enabled",    True)),
        "entrepot_trial_days": int(getattr(cfg, "entrepot_trial_days", 30)),
        "entrepot_trial_all":  bool(getattr(cfg, "entrepot_trial_all", False)),
    }


@router.get("/status")
def get_billing_status(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Returns the current subscription status for the tenant."""
    tenant = _get_tenant(db, current_user)

    trial_end = tenant.trial_ends_at

    from api.core.tenant import GRACE_DAYS
    now = now_local()
    days_left = None
    is_grace = False
    grace_days_left = None

    if trial_end and tenant.status in ("trial", "expired"):
        delta = trial_end - now
        if delta.total_seconds() > 0:
            days_left = max(0, ceil(delta.total_seconds() / 86400))
        else:
            # In grace period
            is_grace = True
            grace_end = trial_end + timedelta(days=GRACE_DAYS)
            grace_delta = grace_end - now
            grace_days_left = max(0, ceil(grace_delta.total_seconds() / 86400))

    sub_end = getattr(tenant, "subscription_ends_at", None)

    return {
        "status": tenant.status,
        "business_name": tenant.business_name,
        "owner_email": tenant.owner_email,
        "trial_ends_at": trial_end.isoformat() if trial_end else None,
        "days_left": days_left,
        "is_grace": is_grace,
        "grace_days_left": grace_days_left,
        "subscription_started_at": tenant.subscription_started_at.isoformat()
            if tenant.subscription_started_at else None,
        "subscription_ends_at": sub_end.isoformat() if sub_end else None,
        "has_stripe": bool(tenant.stripe_subscription_id),
        "max_caisses": tenant.max_caisses,
        "max_depots": getattr(tenant, "max_depots", 1),
    }


@router.get("/plan-usage")
def get_plan_usage(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Retourne le détail d'utilisation du plan : caisses + dépôts + total mensuel calculé."""
    tenant = _get_tenant(db, current_user)
    cfg    = db.query(PlatformConfig).first()
    return _compute_plan_usage(tenant, db, cfg)


def _build_license_payload(tenant: "Tenant", db: Session) -> dict:
    """Build the raw license payload dict (shared by both license endpoints)."""
    now         = datetime.now(timezone.utc)
    valid_until = now + timedelta(days=7)

    trial_end = tenant.trial_ends_at
    if trial_end and trial_end.tzinfo is None:
        trial_end = trial_end.replace(tzinfo=timezone.utc)

    sub_end = getattr(tenant, "subscription_ends_at", None)
    if sub_end and sub_end.tzinfo is None:
        sub_end = sub_end.replace(tzinfo=timezone.utc)

    cfg   = db.query(PlatformConfig).first()
    usage = _compute_plan_usage(tenant, db, cfg)

    return {
        "tenant_id":            tenant.id,
        "tenant_type":          getattr(tenant, "type", "shared"),
        "self_hosted_url":      getattr(tenant, "self_hosted_url", None) or None,
        "can_manage_tenants":   getattr(tenant, "can_manage_tenants", False),
        "status":               tenant.status,
        "issued_at":            now.isoformat(),
        "valid_until":          valid_until.isoformat(),
        "trial_ends_at":        trial_end.isoformat() if trial_end else None,
        "subscription_ends_at": sub_end.isoformat() if sub_end else None,
        **usage,
    }


def _sign_payload(payload: dict) -> dict:
    """Sign a payload dict with IDENTITY_PRIVATE_KEY. Returns {data, signature}."""
    import json
    import base64
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    raw_key = settings.IDENTITY_PRIVATE_KEY
    if not raw_key:
        raise HTTPException(503, "Identité serveur non configurée (IDENTITY_PRIVATE_KEY)")
    try:
        key_bytes  = base64.b64decode(raw_key)
        priv       = Ed25519PrivateKey.from_private_bytes(key_bytes)
        data_bytes = json.dumps(payload, separators=(",", ":")).encode()
        signature  = priv.sign(data_bytes)
        return {
            "data":      base64.b64encode(data_bytes).decode(),
            "signature": base64.b64encode(signature).decode(),
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, f"Erreur signature licence: {exc}")


@router.get("/license-sync-proxy")
def get_license_sync_proxy(
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Called by self-hosted / local servers proxying for their Flutter clients.
    Accepts a sync token (Bearer) instead of a user JWT.
    Returns a signed license blob (signed with IDENTITY_PRIVATE_KEY on posconnect.ht).
    """
    from api.routes.sync import _decode_sync_token

    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(401, "Token de synchronisation requis")

    claims = _decode_sync_token(auth_header[7:])
    tenant = db.query(Tenant).filter(Tenant.id == claims["tenant_id"]).first()
    if not tenant:
        raise HTTPException(404, "Tenant introuvable")

    return _sign_payload(_build_license_payload(tenant, db))


@router.get("/license")
def get_license(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """
    Returns a signed license blob the Flutter app caches locally.
    - If BILLING_URL is configured (self-hosted / local server): proxies to
      posconnect.ht using the stored sync token — transparent to Flutter clients.
    - Otherwise (running ON posconnect.ht): signs and returns directly.
    Signed with IDENTITY_PRIVATE_KEY (Ed25519) — verifiable without internet.
    """
    # ── Proxy mode: self-hosted / local server ────────────────────────────────
    # BILLING_URL is set when this server is NOT posconnect.ht (set by wizard).
    # In that case, proxy to posconnect.ht using the stored sync token so that
    # the signed blob comes from posconnect.ht (Flutter verifies with hardcoded key).
    import httpx as _httpx

    billing_url  = (settings.BILLING_URL or "").rstrip("/")
    sync_token   = settings.CLOUD_SYNC_TOKEN or ""

    if billing_url and sync_token:
        try:
            r = _httpx.get(
                f"{billing_url}/api/billing/license-sync-proxy",
                headers={"Authorization": f"Bearer {sync_token}"},
                timeout=10,
            )
            r.raise_for_status()
            return r.json()
        except _httpx.HTTPStatusError as exc:
            raise HTTPException(exc.response.status_code,
                                f"Erreur billing proxy: {exc.response.text[:200]}")
        except Exception as exc:
            raise HTTPException(503, f"Serveur de billing inaccessible: {exc}")

    # ── Direct mode: this IS posconnect.ht ───────────────────────────────────
    tenant = _get_tenant(db, current_user)
    try:
        payload = _build_license_payload(tenant, db)
    except Exception as exc:
        raise HTTPException(500, f"Erreur construction licence: {exc}")
    return _sign_payload(payload)


@router.get("/caisse-count")
def get_caisse_count(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Retourne le décompte caisses + dépôts vs limites du plan (alias de plan-usage)."""
    tenant = _get_tenant(db, current_user)
    cfg    = db.query(PlatformConfig).first()
    usage  = _compute_plan_usage(tenant, db, cfg)
    # Compatibilité avec les anciens champs
    return {
        **usage,
        "current_caisses": usage["current_caisses"],
        "max_caisses":     usage["max_caisses"],
        "over_limit":      usage["extra_caisses"] > 0 or usage["extra_depots"] > 0,
        "extra_count":     usage["extra_caisses"],
        "price_per_extra_htg": usage["price_per_extra_caisse_htg"],
        "price_per_extra_usd": usage["price_per_extra_caisse_usd"],
    }


def _list_payments_for_tenant(db: Session, tenant: Tenant) -> list[dict]:
    payments = (
        db.query(BillingPayment)
        .filter(BillingPayment.tenant_id == tenant.id)
        .order_by(BillingPayment.created_at.desc())
        .all()
    )
    result = []
    for p in payments:
        period_start = try_decrypt_date(p.period_start, p.tenant_id)
        period_end   = try_decrypt_date(p.period_end,   p.tenant_id)
        result.append({
            "id": p.id,
            "invoice_number": p.invoice_number,
            "method": p.method,
            "amount": float(p.amount),
            "currency": p.currency,
            "status": p.status,
            "reference": p.reference,
            "description": p.description,
            "paid_at": p.paid_at.isoformat() if p.paid_at else None,
            "period_start": period_start.isoformat() if period_start else None,
            "period_end":   period_end.isoformat()   if period_end   else None,
            "created_at": p.created_at.isoformat(),
        })
    return result


@router.get("/payments")
def list_payments(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Returns all billing payments for the current tenant, newest first.

    BillingPayment est une donnée cloud uniquement (jamais synchronisée vers
    les installations locales — voir SYNC_ENTITIES/_MODEL_MAP). Sur un
    serveur local/self-hosted (BILLING_URL configuré), on doit donc toujours
    aller chercher cette liste sur posconnect.ht, sinon elle apparaît
    perpétuellement vide (aucun BillingPayment n'existe jamais localement).
    """
    billing_url = (settings.BILLING_URL or "").rstrip("/")
    sync_token  = settings.CLOUD_SYNC_TOKEN or ""

    if billing_url and sync_token:
        import httpx as _httpx
        try:
            r = _httpx.get(
                f"{billing_url}/api/billing/payments-sync-proxy",
                headers={"Authorization": f"Bearer {sync_token}"},
                timeout=15,
            )
            r.raise_for_status()
            return r.json()
        except _httpx.HTTPStatusError as exc:
            raise HTTPException(exc.response.status_code,
                                f"Erreur billing proxy: {exc.response.text[:200]}")
        except Exception as exc:
            raise HTTPException(503, f"Serveur de billing inaccessible: {exc}")

    tenant = _get_tenant(db, current_user)
    return _list_payments_for_tenant(db, tenant)


@router.get("/payments-sync-proxy")
def get_payments_sync_proxy(request: Request, db: Session = Depends(get_db)):
    """Cloud-side counterpart of list_payments, appelé par un serveur local/
    self-hosted (voir license-sync-proxy pour le même principe). Authentifié
    par sync token, pas par JWT utilisateur (le JWT local n'est pas valide
    sur le cloud — clé de signature propre à chaque serveur)."""
    from api.routes.sync import _decode_sync_token

    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(401, "Token de synchronisation requis")

    claims = _decode_sync_token(auth_header[7:])
    tenant = db.query(Tenant).filter(Tenant.id == claims["tenant_id"]).first()
    if not tenant:
        raise HTTPException(404, "Tenant introuvable")

    return _list_payments_for_tenant(db, tenant)


@router.post("/checkout/stripe")
def create_stripe_checkout(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_UPDATE)),
):
    """Creates a Stripe Checkout session and returns the URL."""
    stripe_secret = getattr(settings, "STRIPE_SECRET_KEY", "")
    stripe_price  = getattr(settings, "STRIPE_PRICE_ID", "")
    success_url   = getattr(settings, "STRIPE_SUCCESS_URL", "")
    cancel_url    = getattr(settings, "STRIPE_CANCEL_URL", "")

    if not stripe_secret or not stripe_price:
        raise HTTPException(
            status_code=503,
            detail="Paiement Stripe non configuré. Contactez l'administrateur.",
        )

    tenant = _get_tenant(db, current_user)

    try:
        import stripe as stripe_lib
        stripe_lib.api_key = stripe_secret

        session = stripe_lib.checkout.Session.create(
            mode="subscription",
            line_items=[{"price": stripe_price, "quantity": 1}],
            customer_email=tenant.owner_email,
            client_reference_id=tenant.id,
            success_url=success_url or "https://posconnect.ht/billing?success=1",
            cancel_url=cancel_url or "https://posconnect.ht/billing?cancelled=1",
        )
        return {"checkout_url": session.url}
    except ImportError:
        raise HTTPException(status_code=503, detail="Module stripe non installé côté serveur")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur Stripe: {str(e)}")


def _generate_and_commit_payments(
    db: Session, prefix: str,
    build: Callable[[int], list],
    max_attempts: int = 5,
) -> list:
    """Crée et commite un lot de BillingPayment dont le numéro de facture suit
    la forme f"{prefix}{n:04d}", n généré par COUNT()+1 — pas atomique : deux
    soumissions concurrentes (ou un double-clic/retry après une erreur
    transitoire) peuvent tomber sur le même numéro, provoquant une
    IntegrityError sur la contrainte unique invoice_number. Retente depuis un
    COUNT() frais dans ce cas plutôt que remonter une erreur 500 au tenant.

    build(base_count) doit créer les BillingPayment (db.add() inclus) en
    numérotant à partir de base_count, et retourner la liste créée."""
    last_exc: IntegrityError | None = None
    for _ in range(max_attempts):
        base_count = db.query(BillingPayment).filter(
            BillingPayment.invoice_number.like(f"{prefix}%"),
        ).count()
        payments = build(base_count)
        try:
            db.commit()
            return payments
        except IntegrityError as exc:
            db.rollback()
            last_exc = exc
    raise last_exc


@router.post("/submit-payment", status_code=201)
def submit_payment(
    body: SubmitPaymentRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_UPDATE)),
):
    """
    Tenant submits proof of a MonCash/NatCash payment.
    Creates a BillingPayment with status='pending'.
    A superadmin must confirm it via PATCH /api/admin/payments/{id}/confirm.
    """
    plan_type = body.plan_type if body.plan_type in ("monthly", "annual") else "monthly"
    months = 12 if plan_type == "annual" else max(1, min(body.months, 12))

    tenant = _get_tenant(db, current_user)
    cfg    = db.query(PlatformConfig).first()
    usage  = _compute_plan_usage(tenant, db, cfg)

    if plan_type == "annual":
        discount_pct = float(getattr(cfg, "annual_discount_pct", 20) if cfg else 20)
        amount = usage["total_monthly_htg"] * 12 * (1 - discount_pct / 100)
    else:
        amount = usage["total_monthly_htg"] * months

    now = now_local()
    year   = now.year
    prefix = f"PEND-{year}-"

    plan_label   = "Annuel (-{}%)".format(int(getattr(cfg, "annual_discount_pct", 20) if cfg else 20)) if plan_type == "annual" else f"{months} mois"
    method_label = {"cash": "Espèces", "moncash": "MonCash", "natcash": "NatCash"}.get(body.method, "Manuel")
    days = 365 if plan_type == "annual" else 30 * months

    def _build(base_count: int) -> list:
        payment = BillingPayment(
            tenant_id=tenant.id,
            invoice_number=f"{prefix}{base_count + 1:04d}",
            method=body.method,
            amount=amount,
            currency="HTG",
            months=months,
            status="pending",
            reference=body.reference,
            plan_type=plan_type,
            # Séparateur ASCII (pas d'em dash "—") : le reçu PDF utilise la police
            # par défaut du package `pdf` (Helvetica/WinAnsi), qui ne couvre pas
            # U+2014 et affichait un caractère de remplacement "□" à la place.
            description=f"Demande {method_label} - {plan_label} ({amount:.0f} HTG) - en attente de validation",
            paid_at=None,
            period_start=encrypt_date(now, tenant.id),
            period_end=encrypt_date(now + timedelta(days=days), tenant.id),
        )
        db.add(payment)
        return [payment]

    payment = _generate_and_commit_payments(db, prefix, _build)[0]
    db.refresh(payment)

    return {
        "status":         "pending",
        "invoice_number": payment.invoice_number,
        "payment_id":     payment.id,
        "plan_type":      plan_type,
        "amount_htg":     round(amount, 2),
        "message":        "Votre paiement a été soumis. Un administrateur le validera sous peu.",
    }


def _submit_register_payment_for_tenant(
    db: Session, tenant: Tenant, body: "SubmitRegisterPaymentRequest",
) -> dict:
    """
    Tenant soumet un paiement pour une ou plusieurs caisses spécifiques.
    Le superadmin confirme via PATCH /api/admin/payments/{id}/confirm.
    Les jours restants de chaque caisse sont additionnés lors de la confirmation.
    """
    if not body.register_ids:
        raise HTTPException(status_code=400, detail="Aucune caisse spécifiée")

    plan_type = body.plan_type if body.plan_type in ("monthly", "annual") else "monthly"
    months = 12 if plan_type == "annual" else max(1, min(body.months, 12))

    # Vérifier que toutes les caisses appartiennent bien à ce tenant
    registers = db.query(PosRegister).filter(
        PosRegister.id.in_(body.register_ids),
        PosRegister.tenant_id == tenant.id,
    ).all()
    if len(registers) != len(body.register_ids):
        raise HTTPException(status_code=404, detail="Une ou plusieurs caisses introuvables")

    cfg = db.query(PlatformConfig).first()
    price_per_caisse_htg = float(getattr(cfg, "price_per_extra_caisse_htg", 500) if cfg else 500)
    renewal_price_per_caisse_htg = float(getattr(cfg, "renewal_price_per_caisse_htg", price_per_caisse_htg) if cfg else price_per_caisse_htg)
    discount_pct = float(getattr(cfg, "annual_discount_pct", 20) if cfg else 20)

    import json as _json
    from collections import defaultdict as _defaultdict

    plan_label   = "Annuel" if plan_type == "annual" else f"{months} mois"
    method_label = {"cash": "Espèces", "moncash": "MonCash", "natcash": "NatCash"}.get(body.method, "Manuel")
    days = 365 if plan_type == "annual" else 30 * months
    now  = now_local()
    year = now.year
    prefix = f"REG-{year}-"

    def _unit_price(reg: PosRegister) -> float:
        started = getattr(reg, "subscription_started_at", None)
        price, _ = _renewal_pricing(started, now, price_per_caisse_htg, renewal_price_per_caisse_htg)
        return price

    # Grouper par warehouse → une ligne dans l'historique par dépôt
    by_wh: dict[str, list] = _defaultdict(list)
    for reg in registers:
        by_wh[reg.warehouse_id or "__none__"].append(reg)

    def _build(base_count: int) -> list:
        created = []
        for idx, (wh_id, wh_regs) in enumerate(by_wh.items()):
            unit_sum = sum(_unit_price(r) for r in wh_regs)
            if plan_type == "annual":
                wh_amount = unit_sum * 12 * (1 - discount_pct / 100)
            else:
                wh_amount = unit_sum * months

            wh_name = "Sans dépôt"
            if wh_id != "__none__":
                wh_obj = db.query(Warehouse).filter_by(id=wh_id, tenant_id=tenant.id).first()
                if wh_obj:
                    wh_name = wh_obj.name

            invoice_number = f"{prefix}{base_count + idx + 1:04d}"
            reg_names = ", ".join(r.name for r in wh_regs)

            payment = BillingPayment(
                tenant_id=tenant.id,
                invoice_number=invoice_number,
                method=body.method,
                amount=wh_amount,
                currency="HTG",
                months=months,
                status="pending",
                reference=body.reference,
                plan_type=plan_type,
                register_ids_json=_json.dumps([r.id for r in wh_regs]),
                # Voir le commentaire équivalent ci-dessus (submit_payment) — même
                # correctif d'encodage pour le reçu PDF.
                description=f"{wh_name} - {reg_names} - {method_label} - {plan_label} ({wh_amount:.0f} HTG)",
                paid_at=None,
                period_start=encrypt_date(now, tenant.id),
                period_end=encrypt_date(now + timedelta(days=days), tenant.id),
            )
            db.add(payment)
            created.append(payment)
        return created

    payments_created = _generate_and_commit_payments(db, prefix, _build)
    total_amount = sum(p.amount for p in payments_created)

    return {
        "status":         "pending",
        "payment_count":  len(payments_created),
        "plan_type":      plan_type,
        "register_count": len(registers),
        "amount_htg":     round(total_amount, 2),
        "message":        "Paiement soumis. Un administrateur le validera sous peu.",
    }


@router.post("/submit-register-payment", status_code=201)
def submit_register_payment(
    body: SubmitRegisterPaymentRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Point d'entrée appelé par l'app (bureau/web). Sur un serveur local/
    self-hosted (BILLING_URL configuré), proxie vers posconnect.ht — sinon
    la demande de paiement est créée dans la base LOCALE, où l'admin cloud
    ne la voit jamais (BillingPayment n'est pas synchronisé, voir
    _list_payments_for_tenant). Même principe que get_license/license-sync-proxy."""
    billing_url = (settings.BILLING_URL or "").rstrip("/")
    sync_token  = settings.CLOUD_SYNC_TOKEN or ""

    if billing_url and sync_token:
        import httpx as _httpx
        try:
            r = _httpx.post(
                f"{billing_url}/api/billing/submit-register-payment-sync-proxy",
                json=body.model_dump(),
                headers={"Authorization": f"Bearer {sync_token}"},
                timeout=15,
            )
            r.raise_for_status()
            return r.json()
        except _httpx.HTTPStatusError as exc:
            raise HTTPException(exc.response.status_code,
                                f"Erreur billing proxy: {exc.response.text[:200]}")
        except Exception as exc:
            raise HTTPException(503, f"Serveur de billing inaccessible: {exc}")

    tenant = _get_tenant(db, current_user)
    return _submit_register_payment_for_tenant(db, tenant, body)


@router.post("/submit-register-payment-sync-proxy", status_code=201)
def submit_register_payment_sync_proxy(
    body: SubmitRegisterPaymentRequest, request: Request, db: Session = Depends(get_db),
):
    """Cloud-side counterpart, authentifié par sync token (voir
    payments-sync-proxy / license-sync-proxy pour le même principe)."""
    from api.routes.sync import _decode_sync_token

    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(401, "Token de synchronisation requis")

    claims = _decode_sync_token(auth_header[7:])
    tenant = db.query(Tenant).filter(Tenant.id == claims["tenant_id"]).first()
    if not tenant:
        raise HTTPException(404, "Tenant introuvable")

    return _submit_register_payment_for_tenant(db, tenant, body)


def _submit_entrepot_payment_for_tenant(
    db: Session, tenant: Tenant, body: "SubmitEntrepotPaymentRequest",
) -> dict:
    """
    Tenant soumet un paiement pour un ou plusieurs entrepôts spécifiques.
    Le superadmin confirme via PATCH /api/admin/payments/{id}/confirm, qui
    étend Warehouse.subscription_ends_at (pas d'essai gratuit — voir
    entrepot_service._assert_paid).
    """
    if not body.entrepot_ids:
        raise HTTPException(status_code=400, detail="Aucun entrepôt spécifié")

    plan_type = body.plan_type if body.plan_type in ("monthly", "annual") else "monthly"
    months = 12 if plan_type == "annual" else max(1, min(body.months, 12))

    entrepots = db.query(Warehouse).filter(
        Warehouse.id.in_(body.entrepot_ids),
        Warehouse.tenant_id == tenant.id,
        Warehouse.is_entrepot == True,  # noqa: E712
    ).all()
    if len(entrepots) != len(body.entrepot_ids):
        raise HTTPException(status_code=404, detail="Un ou plusieurs entrepôts introuvables")

    cfg = db.query(PlatformConfig).first()
    price_per_entrepot_htg = float(getattr(cfg, "price_per_extra_depot_htg", 500) if cfg else 500)
    renewal_price_per_entrepot_htg = float(getattr(cfg, "renewal_price_per_depot_htg", price_per_entrepot_htg) if cfg else price_per_entrepot_htg)
    discount_pct = float(getattr(cfg, "annual_discount_pct", 20) if cfg else 20)

    import json as _json

    plan_label   = "Annuel" if plan_type == "annual" else f"{months} mois"
    method_label = {"cash": "Espèces", "moncash": "MonCash", "natcash": "NatCash"}.get(body.method, "Manuel")
    days = 365 if plan_type == "annual" else 30 * months
    now  = now_local()
    year = now.year
    prefix = f"ENT-{year}-"

    # Pas de subscription_started_at sur Warehouse — created_at sert d'ancre
    # pour la première année (voir clarification utilisateur).
    unit_sum = sum(
        _renewal_pricing(e.created_at, now, price_per_entrepot_htg, renewal_price_per_entrepot_htg)[0]
        for e in entrepots
    )
    if plan_type == "annual":
        amount = unit_sum * 12 * (1 - discount_pct / 100)
    else:
        amount = unit_sum * months

    ent_names = ", ".join(e.name for e in entrepots)

    def _build(base_count: int) -> list:
        payment = BillingPayment(
            tenant_id=tenant.id,
            invoice_number=f"{prefix}{base_count + 1:04d}",
            method=body.method,
            amount=amount,
            currency="HTG",
            months=months,
            status="pending",
            reference=body.reference,
            plan_type=plan_type,
            entrepot_ids_json=_json.dumps([e.id for e in entrepots]),
            description=f"{ent_names} - {method_label} - {plan_label} ({amount:.0f} HTG)",
            paid_at=None,
            period_start=encrypt_date(now, tenant.id),
            period_end=encrypt_date(now + timedelta(days=days), tenant.id),
        )
        db.add(payment)
        return [payment]

    payment = _generate_and_commit_payments(db, prefix, _build)[0]
    db.refresh(payment)

    return {
        "status":          "pending",
        "invoice_number":  payment.invoice_number,
        "payment_id":      payment.id,
        "plan_type":       plan_type,
        "entrepot_count":  len(entrepots),
        "amount_htg":      round(amount, 2),
        "message":         "Paiement soumis. Un administrateur le validera sous peu.",
    }


@router.post("/submit-entrepot-payment", status_code=201)
def submit_entrepot_payment(
    body: SubmitEntrepotPaymentRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CONFIG_READ)),
):
    """Point d'entrée appelé par l'app — même principe de proxy que
    submit_register_payment (voir ce commentaire)."""
    billing_url = (settings.BILLING_URL or "").rstrip("/")
    sync_token  = settings.CLOUD_SYNC_TOKEN or ""

    if billing_url and sync_token:
        import httpx as _httpx
        try:
            r = _httpx.post(
                f"{billing_url}/api/billing/submit-entrepot-payment-sync-proxy",
                json=body.model_dump(),
                headers={"Authorization": f"Bearer {sync_token}"},
                timeout=15,
            )
            r.raise_for_status()
            return r.json()
        except _httpx.HTTPStatusError as exc:
            raise HTTPException(exc.response.status_code,
                                f"Erreur billing proxy: {exc.response.text[:200]}")
        except Exception as exc:
            raise HTTPException(503, f"Serveur de billing inaccessible: {exc}")

    tenant = _get_tenant(db, current_user)
    return _submit_entrepot_payment_for_tenant(db, tenant, body)


@router.post("/submit-entrepot-payment-sync-proxy", status_code=201)
def submit_entrepot_payment_sync_proxy(
    body: SubmitEntrepotPaymentRequest, request: Request, db: Session = Depends(get_db),
):
    """Cloud-side counterpart, authentifié par sync token (voir
    submit-register-payment-sync-proxy pour le même principe)."""
    from api.routes.sync import _decode_sync_token

    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(401, "Token de synchronisation requis")

    claims = _decode_sync_token(auth_header[7:])
    tenant = db.query(Tenant).filter(Tenant.id == claims["tenant_id"]).first()
    if not tenant:
        raise HTTPException(404, "Tenant introuvable")

    return _submit_entrepot_payment_for_tenant(db, tenant, body)
