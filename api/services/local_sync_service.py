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
from datetime import datetime, timezone
from typing import Any

import httpx
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.orm import Session

from api.core.config import settings
from api.models.SyncState import SyncState
from api.models.Category import Category
from api.models.Product import Product
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

_log = logging.getLogger("pos.sync")

# ── Entity registry ──────────────────────────────────────────────────────────
# direction: "push" = local→cloud only | "pull" = cloud→local only | "both" = bidirectional

SYNC_ENTITIES: list[dict] = [
    # ── Reference data ──────────────────────────────────────────────────────
    # Warehouses : bidirectionnel — un admin sur app bureau peut créer un dépôt local
    # qui doit remonter vers le cloud pour être visible partout.
    {"type": "warehouse",              "model": Warehouse,            "direction": "both"},
    {"type": "category",               "model": Category,             "direction": "both"},
    {"type": "supplier",               "model": Supplier,             "direction": "both"},
    {"type": "product",                "model": Product,              "direction": "both"},
    {"type": "customer",               "model": Customer,             "direction": "both"},
    {"type": "user",                   "model": User,                 "direction": "both"},
    {"type": "pos_register",           "model": PosRegister,         "direction": "both"},
    # ── Sales & payments ────────────────────────────────────────────────────
    {"type": "sale",                   "model": Sale,                 "direction": "push"},
    {"type": "sale_item",              "model": SaleItem,             "direction": "push"},
    {"type": "payment",                "model": Payment,              "direction": "both"},
    {"type": "return_record",          "model": ReturnRecord,         "direction": "both"},
    # ── Purchases ───────────────────────────────────────────────────────────
    {"type": "purchase",               "model": Purchase,             "direction": "both"},
    {"type": "purchase_item",          "model": PurchaseItem,         "direction": "both"},
    {"type": "purchase_receipt",       "model": PurchaseReceipt,      "direction": "both"},
    {"type": "purchase_receipt_item",  "model": PurchaseReceiptItem,  "direction": "both"},
    # ── Stock & inventory ───────────────────────────────────────────────────
    {"type": "stock_movement",         "model": StockMovement,        "direction": "push"},
    {"type": "inventory_record",       "model": InventoryRecord,      "direction": "push"},
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
]

# Columns excluded when sending to cloud (cloud assigns its own tenant_id via sync token)
_EXCLUDE_PUSH = {"tenant_id", "password", "password_hash"}  # never push credentials to cloud
_EXCLUDE_PULL: set[str] = set()
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
    result = []
    for r in rows:
        d = _row_to_dict(r, exclude)
        # Convert datetime → ISO string
        for k, v in d.items():
            if isinstance(v, datetime):
                d[k] = v.isoformat()
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

    # Cycle start in UTC — MySQL connection is forced to UTC (SET time_zone='+00:00')
    # so updated_at comparisons are consistent across all timezones.
    cycle_start = datetime.now(timezone.utc)

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
                    lp = state.last_push_at
                    if lp.tzinfo is None:
                        lp = lp.replace(tzinfo=timezone.utc)
                    query = query.filter(model.updated_at > lp)
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

        # ── PULL (pull / both) ────────────────────────────────────────────
        if direction in ("pull", "both"):
            try:
                since = state.last_pull_at.isoformat() if state.last_pull_at else "1970-01-01T00:00:00+00:00"
                resp = _http_get(
                    f"{url}/api/sync/pull",
                    params={"entity_type": etype, "since": since},
                    headers=_headers(token),
                )
                records = resp.json().get("records", [])

                col_names = {c.key for c in sa_inspect(model).columns}

                applied = 0
                skipped = 0
                for rec in records:
                    existing = db.get(model, rec["id"])

                    # Secondary lookup for entities with a unique slug/username:
                    # the local record may have been created with a different UUID
                    # before sync was configured (e.g. the admin user 'my-store').
                    if existing is None:
                        for unique_col in ("username", "slug", "reference"):
                            if unique_col in col_names and rec.get(unique_col):
                                existing = db.query(model).filter(
                                    getattr(model, unique_col) == rec[unique_col]
                                ).first()
                                if existing:
                                    break

                    if existing is None:
                        coerced = _coerce_for_db(model, rec)
                        fields = {k: v for k, v in coerced.items() if k in col_names}
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
                        if local_ts and local_ts.tzinfo is None:
                            local_ts = local_ts.replace(tzinfo=timezone.utc)
                        if remote_ts and (not local_ts or remote_ts > local_ts):
                            coerced = _coerce_for_db(model, rec)
                            for k, v in coerced.items():
                                if k in col_names and k != "id":
                                    setattr(existing, k, v)
                            applied += 1

                summary["pulled"][etype] = applied
                state.records_pulled += applied
                state.last_pull_at = datetime.now(timezone.utc)
                state.last_error = None
            except Exception as exc:
                msg = f"pull {etype}: {exc}"
                _log.warning(msg)
                summary["errors"].append(msg)

    db.commit()
    summary["ok"] = len(summary["errors"]) == 0
    return summary


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except Exception:
        return None


def _coerce_for_db(model: Any, record: dict) -> dict:
    """
    Convert ISO datetime strings to Python datetime objects for DateTime columns.
    SQLite's DateTime type rejects raw strings; MySQL accepts them silently.
    """
    from sqlalchemy import DateTime as _DT, inspect as _insp
    try:
        mapper = _insp(model)
        cols = {c.key: c for c in mapper.columns}
    except Exception:
        return record

    result = {}
    for k, v in record.items():
        if isinstance(v, str) and k in cols:
            col_type = cols[k].type
            if isinstance(col_type, _DT):
                parsed = _parse_dt(v)
                v = parsed if parsed is not None else v
        result[k] = v
    return result


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
