"""
Local sync service: pushes local records to the cloud and pulls updates back.
Runs on the LOCAL server only (DB_TYPE=sqlite or configured local MySQL).

Flow:
  1. Authenticate with cloud → get or reuse sync token
  2. For each entity: push rows where updated_at > last_push_at
  3. For bidirectional entities: pull rows where updated_at > last_pull_at
  4. Update SyncState timestamps
"""
import logging
from datetime import datetime, timedelta
from typing import Any

import httpx
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.orm import Session

from api.core.config import settings
from api.core.dt_coerce import coerce_datetimes as _coerce_dt_shared, coerce_enums as _coerce_enums_shared, now_local
from api.models.SyncState import SyncState
from api.models.Category import Category
from api.models.Discount import Discount
from api.models.Product import Product
from api.models.ProductWarehousePrice import ProductWarehousePrice
from api.models.Customer import Customer
from api.models.Supplier import Supplier
from api.models.User import User
from api.models.Sale import Sale
from api.models.SaleItem import SaleItem
from api.models.Payment import Payment
from api.models.Purchase import Purchase
from api.models.PurchaseItem import PurchaseItem
from api.models.ReturnRecord import ReturnRecord
from api.models.PosRegister import PosRegister
from api.models.Debt import Debt
from api.models.Invoice import Invoice, InvoiceItem
from api.models.Proforma import Proforma, ProformaItem
from api.models.StockMovement import StockMovement
from api.models.InventoryRecord import InventoryRecord
from api.models.PurchaseReceipt import PurchaseReceipt
from api.models.PurchaseReceiptItem import PurchaseReceiptItem
from api.models.AppConfig import AppConfig
from api.models.CashierSession import CashierSession
from api.models.AuditLog import AuditLog
from api.models.Warehouse import Warehouse
from api.models.EmployeeProfile import EmployeeProfile
from api.models.PayrollPeriod import PayrollPeriod
from api.models.PayrollEntry import PayrollEntry
from api.models.EmployeeLoan import EmployeeLoan
from api.models.PayrollLoanDeduction import PayrollLoanDeduction
from api.models.RestaurantTable import RestaurantTable
from api.models.RoomAttribute import RoomAttribute
from api.models.MenuItem import MenuItem
from api.models.ModifierGroup import ModifierGroup, ModifierOption
from api.models.RestaurantOrder import RestaurantOrder, RestaurantOrderItem
from api.models.HousekeepingTask import HousekeepingTask
from api.models.ClientSabotage import ClientSabotage
from api.models.Depot import Depot
from api.models.Retrait import Retrait

_log = logging.getLogger("pos.sync")

# ── Entity registry ──────────────────────────────────────────────────────────
# direction: "push" = local→cloud only | "pull" = cloud→local only | "both" = bidirectional

SYNC_ENTITIES: list[dict] = [
    # ── Reference data ──────────────────────────────────────────────────────
    # Warehouses : bidirectionnel — un admin sur app bureau peut créer un dépôt local
    # qui doit remonter vers le cloud pour être visible partout.
    {"type": "warehouse",              "model": Warehouse,            "direction": "both"},
    {"type": "category",               "model": Category,             "direction": "both"},
    {"type": "discount",               "model": Discount,             "direction": "both"},
    {"type": "supplier",               "model": Supplier,             "direction": "both"},
    {"type": "product",                "model": Product,              "direction": "both"},
    {"type": "product_warehouse_price", "model": ProductWarehousePrice, "direction": "both"},
    {"type": "customer",               "model": Customer,             "direction": "both"},
    {"type": "user",                   "model": User,                 "direction": "both"},
    {"type": "pos_register",           "model": PosRegister,         "direction": "both"},
    # ── Sales & payments ────────────────────────────────────────────────────
    # "both" : le bureau doit voir les ventes faites depuis mobile ou web.
    {"type": "sale",                   "model": Sale,                 "direction": "both"},
    {"type": "sale_item",              "model": SaleItem,             "direction": "both"},
    {"type": "payment",                "model": Payment,              "direction": "both"},
    {"type": "return_record",          "model": ReturnRecord,         "direction": "both"},
    # ── Purchases ───────────────────────────────────────────────────────────
    {"type": "purchase",               "model": Purchase,             "direction": "both"},
    {"type": "purchase_item",          "model": PurchaseItem,         "direction": "both"},
    {"type": "purchase_receipt",       "model": PurchaseReceipt,      "direction": "both"},
    {"type": "purchase_receipt_item",  "model": PurchaseReceiptItem,  "direction": "both"},
    # ── Settings (config d'entreprise partagée depuis le cloud) ────────────
    # "pull" uniquement : le cloud admin peut modifier le nom, logo, devise…
    # Les settings imprimante (pos_printer_name etc.) restent locaux.
    {"type": "app_config",             "model": AppConfig,            "direction": "pull"},
    # ── Stock & inventory ───────────────────────────────────────────────────
    {"type": "stock_movement",         "model": StockMovement,        "direction": "both"},
    # "both" : les ajustements faits depuis le web/admin doivent redescendre sur bureau.
    {"type": "inventory_record",       "model": InventoryRecord,      "direction": "both"},
    # ── Invoicing & proformas ───────────────────────────────────────────────
    {"type": "invoice",                "model": Invoice,              "direction": "both"},
    {"type": "invoice_item",           "model": InvoiceItem,          "direction": "both"},
    {"type": "proforma",               "model": Proforma,             "direction": "both"},
    {"type": "proforma_item",          "model": ProformaItem,         "direction": "both"},
    # ── Debts ───────────────────────────────────────────────────────────────
    {"type": "debt",                   "model": Debt,                 "direction": "both"},
    # ── Cashier sessions ────────────────────────────────────────────────────
    {"type": "cashier_session",        "model": CashierSession,       "direction": "push"},
    # ── Audit trail ─────────────────────────────────────────────────────────
    {"type": "audit_log",              "model": AuditLog,             "direction": "push"},
    # ── HR & payroll ────────────────────────────────────────────────────────
    {"type": "employee_profile",       "model": EmployeeProfile,      "direction": "both"},
    {"type": "payroll_period",         "model": PayrollPeriod,        "direction": "both"},
    {"type": "payroll_entry",          "model": PayrollEntry,         "direction": "both"},
    {"type": "employee_loan",          "model": EmployeeLoan,         "direction": "both"},
    {"type": "payroll_loan_deduction", "model": PayrollLoanDeduction, "direction": "both"},
    # ── Restaurant / Hôtel — configuration (bidirectionnel) ─────────────────────
    # Tables et attributs : un admin cloud peut créer/modifier des chambres
    {"type": "restaurant_table", "model": RestaurantTable, "direction": "both"},
    {"type": "room_attribute",   "model": RoomAttribute,   "direction": "both"},
    # Carte du menu : créée en central, visible dans tous les dépôts
    {"type": "menu_item",        "model": MenuItem,        "direction": "both"},
    {"type": "modifier_group",   "model": ModifierGroup,   "direction": "both"},
    {"type": "modifier_option",  "model": ModifierOption,  "direction": "both"},
    # ── Restaurant / Hôtel — données opérationnelles (push uniquement) ──────────
    # Les commandes sont créées localement ; le cloud les reçoit pour reporting
    {"type": "restaurant_order",      "model": RestaurantOrder,     "direction": "push"},
    {"type": "restaurant_order_item", "model": RestaurantOrderItem, "direction": "push"},
    # Tâches housekeeping : historique poussé vers le cloud
    {"type": "housekeeping_task", "model": HousekeepingTask, "direction": "push"},
    # ── Système de Sabotage ──────────────────────────────────────────────────
    {"type": "client_sabotage", "model": ClientSabotage, "direction": "both"},
    {"type": "depot",           "model": Depot,          "direction": "both"},
    {"type": "retrait",         "model": Retrait,        "direction": "both"},
]

# Columns excluded when sending to cloud (cloud assigns its own tenant_id via sync token)
_EXCLUDE_PUSH = {"tenant_id", "password", "password_hash", "offline_hash"}  # never push credentials/hashes to cloud
_EXCLUDE_PULL: set[str] = set()

# Per-entity fields that are device-specific — never overwrite local values from cloud pull
_ENTITY_EXCLUDE_PULL: dict[str, set[str]] = {
    "app_config": {"pos_printer_name", "doc_printer_name", "pos_auto_print", "doc_auto_print"},
}
_PUSH_CHUNK   = 500   # max records per HTTP push request

# Prevents concurrent run_sync calls (auto-loop + manual button)
import threading as _threading
_sync_lock = _threading.Lock()


# ── Helpers ──────────────────────────────────────────────────────────────────

def _row_to_dict(row: Any, exclude: set[str] = frozenset()) -> dict:
    mapper = sa_inspect(type(row))
    return {
        c.key: getattr(row, c.key)
        for c in mapper.columns
        if c.key not in exclude
    }


def _serialize(rows: list, exclude: set[str]) -> list[dict]:
    import enum as _enum
    result = []
    for r in rows:
        d = _row_to_dict(r, exclude)
        for k, v in d.items():
            if isinstance(v, datetime):
                d[k] = v.isoformat()
            elif isinstance(v, _enum.Enum):
                # SaleStatus.paid → "PAID", StockType.in_ → "in", etc.
                d[k] = v.value
            elif hasattr(v, '__float__'):
                d[k] = float(v)
        result.append(d)
    return result


def _get_sync_state(db: Session, entity_type: str) -> SyncState:
    s = db.query(SyncState).filter(SyncState.entity_type == entity_type).first()
    if not s:
        s = SyncState(entity_type=entity_type)
        db.add(s)
        db.flush()
    return s


def _headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def _http_post(url: str, json: dict, headers: dict, timeout: int = 30) -> httpx.Response:
    """POST with 3 retries on transient network errors (1s, 2s, 4s backoff)."""
    import time
    last_exc: Exception | None = None
    for attempt in range(3):
        try:
            resp = httpx.post(url, json=json, headers=headers, timeout=timeout)
            resp.raise_for_status()
            return resp
        except (httpx.ConnectError, httpx.TimeoutException, httpx.RemoteProtocolError) as exc:
            last_exc = exc
            if attempt < 2:
                time.sleep(2 ** attempt)
        except httpx.HTTPStatusError:
            raise  # server errors (4xx/5xx) are not retried
    raise last_exc  # type: ignore[misc]


def _http_get(url: str, params: dict, headers: dict, timeout: int = 30) -> httpx.Response:
    """GET with 3 retries on transient network errors."""
    import time
    last_exc: Exception | None = None
    for attempt in range(3):
        try:
            resp = httpx.get(url, params=params, headers=headers, timeout=timeout)
            resp.raise_for_status()
            return resp
        except (httpx.ConnectError, httpx.TimeoutException, httpx.RemoteProtocolError) as exc:
            last_exc = exc
            if attempt < 2:
                time.sleep(2 ** attempt)
        except httpx.HTTPStatusError:
            raise
    raise last_exc  # type: ignore[misc]


# ── Main sync entry point ────────────────────────────────────────────────────

def _load_sync_credentials() -> tuple[str, str, bool]:
    """Read sync credentials from INI (fresh on every call, multi-worker safe)."""
    from api.core.config import load_ini_config
    cfg = load_ini_config()
    url     = (cfg.get("CLOUD_SYNC_URL") or settings.CLOUD_SYNC_URL or "").rstrip("/")
    token   = cfg.get("CLOUD_SYNC_TOKEN") or settings.CLOUD_SYNC_TOKEN or ""
    enabled = cfg.get("CLOUD_SYNC_ENABLED", settings.CLOUD_SYNC_ENABLED)
    return url, token, bool(enabled)


def run_sync(db: Session) -> dict:
    """
    Runs a full push+pull cycle. Returns a summary dict.
    Requires CLOUD_SYNC_URL and CLOUD_SYNC_TOKEN in pos_server.ini or settings.
    Thread-safe: concurrent calls return immediately with a busy indicator.
    """
    if not _sync_lock.acquire(blocking=False):
        return {"ok": False, "error": "Sync déjà en cours — réessayez dans un instant"}

    try:
        return _run_sync_inner(db)
    finally:
        _sync_lock.release()


def _run_sync_inner(db: Session) -> dict:
    from sqlalchemy import text as _text

    url, token, _ = _load_sync_credentials()

    if not url or not token:
        return {"ok": False, "error": "CLOUD_SYNC_URL ou CLOUD_SYNC_TOKEN non configuré"}

    # Use READ COMMITTED so each query sees the latest committed rows,
    # avoiding stale snapshots from REPEATABLE READ (MySQL default).
    try:
        db.execute(_text("SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED"))
    except Exception:
        pass  # SQLite or unsupported engine — safe to ignore

    # Cycle start en heure locale Haiti — cohérent avec model.updated_at (naïf, Haiti)
    cycle_start = now_local()

    summary = {"pushed": {}, "pulled": {}, "errors": []}

    for entity in SYNC_ENTITIES:
        etype = entity["type"]
        model = entity["model"]
        direction = entity["direction"]

        state = _get_sync_state(db, etype)

        # ── PUSH (push / both) ────────────────────────────────────────────
        if direction in ("push", "both"):
            try:
                query = db.query(model)
                if state.last_push_at:
                    query = query.filter(model.updated_at > state.last_push_at)
                rows = query.all()

                if rows:
                    payload = _serialize(rows, _EXCLUDE_PUSH)
                    total_pushed = 0
                    # Chunk large payloads to avoid timeouts / OOM
                    for i in range(0, len(payload), _PUSH_CHUNK):
                        chunk = payload[i : i + _PUSH_CHUNK]
                        resp = _http_post(
                            f"{url}/api/sync/push",
                            json={"entity_type": etype, "records": chunk},
                            headers=_headers(token),
                        )
                        result = resp.json()
                        total_pushed += result.get("inserted", 0) + result.get("updated", 0)
                    summary["pushed"][etype] = total_pushed
                    state.records_pushed += total_pushed

                # Advance watermark to cycle_start (recorded before queries)
                # to close the race window between query and now().
                state.last_push_at = cycle_start
                state.last_error = None
            except Exception as exc:
                msg = f"push {etype}: {exc}"
                _log.warning(msg)
                state.last_error = msg
                summary["errors"].append(msg)

    db.commit()

    # ── PULL (batch — une requête HTTP au lieu de N) ───────────────────────────
    # Collecte les entités à tirer et leurs curseurs
    pull_entities = [
        (e, _get_sync_state(db, e["type"]))
        for e in SYNC_ENTITIES
        if e["direction"] in ("pull", "both")
    ]

    # Entités récemment passées de "push" à "both" : last_pull_at est None
    # mais last_push_at existe (elles ont déjà été poussées).  Initialiser à
    # 90 jours en arrière pour ne pas aspirer toute l'histoire depuis 1970.
    _PULL_LOOKBACK = timedelta(days=90)
    for e, s in pull_entities:
        if s.last_pull_at is None and s.last_push_at is not None:
            s.last_pull_at = cycle_start - _PULL_LOOKBACK
    db.flush()

    cursors = {
        e["type"]: (s.last_pull_at.isoformat() if s.last_pull_at else "1970-01-01T00:00:00")
        for e, s in pull_entities
    }

    # Essaie le batch ; si le cloud ne supporte pas encore l'endpoint (404 / erreur
    # réseau), revient au pull individuel par entité (rétrocompatible).
    batch: dict = {}
    try:
        br = _http_post(
            f"{url}/api/sync/pull-batch",
            json={"cursors": cursors},
            headers=_headers(token),
        )
        batch = br.json().get("results", {})
    except Exception as exc:
        _log.warning("pull-batch: %s — repli sur pull individuel", exc)

    for entity, state in pull_entities:
        etype  = entity["type"]
        model  = entity["model"]
        since  = cursors[etype]
        try:
            page    = batch.get(etype)
            records: list = list(page["records"]) if page else []

            if page is not None and page.get("has_more"):
                # pagine le reste via le endpoint individuel existant
                cur = page.get("next_since", since)
                for _s in range(200):
                    r2  = _http_get(f"{url}/api/sync/pull", params={"entity_type": etype, "since": cur}, headers=_headers(token))
                    p2  = r2.json()
                    records.extend(p2.get("records", []))
                    if not p2.get("has_more"):
                        break
                    nxt = p2.get("next_since", cur)
                    if nxt == cur:
                        break
                    cur = nxt
            elif page is None:
                # batch indisponible — pull individuel classique
                cur = since
                for _s in range(200):
                    r2  = _http_get(f"{url}/api/sync/pull", params={"entity_type": etype, "since": cur}, headers=_headers(token))
                    p2  = r2.json()
                    records.extend(p2.get("records", []))
                    if not p2.get("has_more"):
                        break
                    nxt = p2.get("next_since", cur)
                    if nxt == cur:
                        break
                    cur = nxt

            col_names = {c.key for c in sa_inspect(model).columns}
            entity_excl = _ENTITY_EXCLUDE_PULL.get(etype, set())
            applied = skipped = 0
            for rec in records:
                existing = db.get(model, rec["id"])
                if existing is None:
                    for unique_col in ("username", "slug", "reference", "email"):
                        if unique_col in col_names and rec.get(unique_col):
                            existing = db.query(model).filter(
                                getattr(model, unique_col) == rec[unique_col]
                            ).first()
                            if existing:
                                break
                    # pos_register n'a pas de colonne unique simple — sa clé
                    # naturelle est composite (tenant_id, device_id). Sans ce
                    # fallback, un doublon existant côté cloud (deux registres
                    # pour le même device_id, contrainte jamais réellement
                    # appliquée sur une table MySQL déjà existante — voir
                    # _repair_duplicate_registers) échoue à l'insert local à
                    # chaque cycle sans jamais se corriger.
                    if existing is None and etype == "pos_register" and rec.get("device_id"):
                        existing = db.query(model).filter(
                            model.tenant_id == rec.get("tenant_id"),
                            model.device_id == rec["device_id"],
                        ).first()
                if existing is None:
                    coerced = _coerce_for_db(model, rec)
                    fields = {k: v for k, v in coerced.items() if k in col_names and k not in entity_excl}
                    try:
                        with db.begin_nested():
                            db.add(model(**fields))
                        applied += 1
                    except Exception as ins_exc:
                        _log.warning("pull insert %s %s: %s", etype, rec.get("id"), ins_exc)
                        skipped += 1
                else:
                    remote_ts = _parse_dt(rec.get("updated_at"))
                    local_ts  = existing.updated_at
                    if remote_ts and (not local_ts or remote_ts > local_ts):
                        coerced = _coerce_for_db(model, rec)
                        for k, v in coerced.items():
                            if k in col_names and k != "id" and k not in entity_excl:
                                setattr(existing, k, v)
                        applied += 1

            summary["pulled"][etype] = applied
            state.records_pulled += applied
            state.last_pull_at = now_local()
            state.last_error = None
        except Exception as exc:
            msg = f"pull {etype}: {exc}"
            _log.warning(msg)
            state.last_error = msg
            summary["errors"].append(msg)

    db.commit()

    # ── Sync tenant billing (trial_ends_at, status, limits) ──────────────────
    # Tenant is not a generic SYNC_ENTITIES model; update its billing fields
    # separately so changes made via admin panel (trial extension, status change)
    # are reflected on every local installation without requiring a re-configure.
    try:
        billing_resp = _http_get(
            f"{url}/api/sync/tenant-billing",
            params={},
            headers=_headers(token),
        )
        b = billing_resp.json()
        from api.models.Tenant import Tenant as _Tenant
        from api.core.config import load_ini_config as _load_ini
        _ini = _load_ini()
        cloud_tid = (_ini.get("CLOUD_TENANT_ID") or _ini.get("cloud_tenant_id") or "").strip()
        local_tenant = (
            db.query(_Tenant).filter(_Tenant.id == cloud_tid).first()
            if cloud_tid else None
        )
        if local_tenant:
            if b.get("trial_ends_at"):
                local_tenant.trial_ends_at = _parse_dt(b["trial_ends_at"])
            if b.get("status"):
                local_tenant.status = b["status"]
            if b.get("max_caisses") is not None:
                local_tenant.max_caisses = int(b["max_caisses"])
            if b.get("max_depots") is not None and hasattr(local_tenant, "max_depots"):
                local_tenant.max_depots = int(b["max_depots"])
            db.commit()
    except Exception as exc:
        _log.warning("sync tenant-billing: %s", exc)

    # ── Sync public platform config (pricing, payment methods) ───────────────
    # Never syncs credentials — only fields listed in _PUBLIC_CONFIG_FIELDS.
    _PUBLIC_CONFIG_FIELDS = (
        "moncash_number", "natcash_number",
        "monthly_price_htg", "monthly_price_usd",
        "trial_days", "trial_included_in_billing", "annual_discount_pct",
        "support_email", "support_whatsapp", "support_address",
        "moncash_mode", "natcash_mode",
        "price_per_extra_caisse_htg", "price_per_extra_caisse_usd",
        "price_per_extra_depot_htg", "price_per_extra_depot_usd",
        "stat_businesses", "stat_transactions_day", "stat_uptime",
        "pricing_plans_json", "logo_url",
        "cash_enabled", "moncash_enabled", "natcash_enabled", "card_enabled",
        "entrepot_trial_days", "entrepot_trial_all",
    )
    try:
        billing_url = (settings.BILLING_URL or url).rstrip("/")
        pub_resp = _http_get(
            f"{billing_url}/api/sync/public-platform-config",
            params={},
            headers=_headers(token),
        )
        pub = pub_resp.json()
        from api.models.PlatformConfig import PlatformConfig as _PC
        local_cfg = db.query(_PC).first()
        if not local_cfg:
            # Un poste local fraîchement installé n'a jamais de ligne
            # PlatformConfig (_ensure_cloud_admin la crée seulement côté
            # cloud — elle skip explicitement dès que CLOUD_SYNC_URL est
            # configuré). Sans cette création, la boucle ci-dessous n'avait
            # jamais rien à mettre à jour : get_billing_config retombait
            # alors indéfiniment sur ses valeurs de repli codées en dur
            # (500 HTG etc.), quels que soient les prix réellement
            # configurés côté admin.
            local_cfg = _PC()
            db.add(local_cfg)
            db.flush()
        if isinstance(pub, dict) and pub:
            for field in _PUBLIC_CONFIG_FIELDS:
                if field in pub:
                    setattr(local_cfg, field, pub[field])
            db.commit()
    except Exception as exc:
        _log.warning("sync public-platform-config: %s", exc)

    summary["ok"] = len(summary["errors"]) == 0
    return summary


def _parse_dt(value: str | None) -> datetime | None:
    from api.core.dt_coerce import parse_dt
    return parse_dt(value)


def _coerce_for_db(model: Any, record: dict) -> dict:
    """
    Convert ISO datetime strings to Python datetime objects for DateTime columns,
    and raw enum-column strings (format API `.value`) back into leur membre Enum
    Python correspondant (voir dt_coerce.coerce_enums — nécessaire quand la DB
    locale est MySQL, qui valide réellement les labels ENUM, contrairement à
    SQLite qui stocke ces colonnes en VARCHAR libre).
    """
    result = _coerce_dt_shared(record, strip_tz=(settings.DB_TYPE == "sqlite"))
    return _coerce_enums_shared(model, result)


# ── Sync status ──────────────────────────────────────────────────────────────

def get_sync_status(db: Session) -> dict:
    from api.core.config import load_ini_config
    url, token, enabled = _load_sync_credentials()
    ini = load_ini_config()
    billing_url = ini.get("BILLING_URL") or ini.get("billing_url") or ""
    # Check lock without blocking: True = sync cycle currently running
    _acquired = _sync_lock.acquire(blocking=False)
    sync_busy = not _acquired
    if _acquired:
        _sync_lock.release()
    states = db.query(SyncState).all()
    return {
        "cloud_url":         url,
        "cloud_owner_email": ini.get("cloud_owner_email", ""),
        "billing_url":       billing_url,
        "configured":        bool(url and token),
        "enabled":           enabled,
        "sync_busy":         sync_busy,
        "entities": [
            {
                "entity_type":    s.entity_type,
                "last_push_at":   s.last_push_at.isoformat() if s.last_push_at else None,
                "last_pull_at":   s.last_pull_at.isoformat() if s.last_pull_at else None,
                "records_pushed": s.records_pushed,
                "records_pulled": s.records_pulled,
                "last_error":     s.last_error,
            }
            for s in states
        ],
    }
