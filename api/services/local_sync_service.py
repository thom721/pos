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

_log = logging.getLogger("pos.sync")

# ── Entity registry ──────────────────────────────────────────────────────────
# direction: "push" = local→cloud only | "both" = bidirectional

SYNC_ENTITIES: list[dict] = [
    {"type": "category",      "model": Category,      "direction": "both"},
    {"type": "supplier",      "model": Supplier,      "direction": "both"},
    {"type": "product",       "model": Product,       "direction": "both"},
    {"type": "customer",      "model": Customer,      "direction": "both"},
    {"type": "user",          "model": User,          "direction": "both"},
    {"type": "pos_register",  "model": PosRegister,   "direction": "both"},
    {"type": "sale",          "model": Sale,          "direction": "push"},
    {"type": "sale_item",     "model": SaleItem,      "direction": "push"},
    {"type": "payment",       "model": Payment,       "direction": "push"},
    {"type": "purchase",      "model": Purchase,      "direction": "push"},
    {"type": "purchase_item", "model": PurchaseItem,  "direction": "push"},
    {"type": "return_record", "model": ReturnRecord,  "direction": "push"},
]

# Columns excluded when sending to cloud (cloud assigns its own tenant_id via sync token)
_EXCLUDE_PUSH = {"tenant_id"}
# Pulled records keep their tenant_id — it matches the local __local__ tenant UUID
# (aligned at install time via connect_tenant using the cloud's tenant UUID).
_EXCLUDE_PULL: set[str] = set()


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
    """
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

    # Record cycle_start BEFORE any queries.
    # Rows updated AFTER this point are caught in the NEXT cycle.
    # Setting last_push_at = cycle_start (not "now after push") prevents
    # permanently missing records created during the sync window.
    cycle_start = datetime.now(timezone.utc)

    summary = {"pushed": {}, "pulled": {}, "errors": []}

    for entity in SYNC_ENTITIES:
        etype = entity["type"]
        model = entity["model"]
        direction = entity["direction"]

        state = _get_sync_state(db, etype)

        # ── PUSH ──────────────────────────────────────────────────────────
        try:
            query = db.query(model)
            if state.last_push_at:
                # Naive vs aware: strip tz for comparison if needed
                lp = state.last_push_at
                if lp.tzinfo is not None:
                    lp = lp.replace(tzinfo=None)
                query = query.filter(model.updated_at > lp)
            rows = query.all()

            if rows:
                payload = _serialize(rows, _EXCLUDE_PUSH)
                resp = httpx.post(
                    f"{url}/api/sync/push",
                    json={"entity_type": etype, "records": payload},
                    headers=_headers(token),
                    timeout=30,
                )
                resp.raise_for_status()
                result = resp.json()
                pushed = result.get("inserted", 0) + result.get("updated", 0)
                summary["pushed"][etype] = pushed
                state.records_pushed += pushed

            # Advance watermark to cycle_start (before queries), not to
            # datetime.now() (after push), to avoid the race window.
            state.last_push_at = cycle_start
            state.last_error = None
        except Exception as exc:
            msg = f"push {etype}: {exc}"
            _log.warning(msg)
            state.last_error = msg
            summary["errors"].append(msg)

        # ── PULL (bidirectional only) ──────────────────────────────────────
        if direction == "both":
            try:
                since = state.last_pull_at.isoformat() if state.last_pull_at else "1970-01-01T00:00:00+00:00"
                resp = httpx.get(
                    f"{url}/api/sync/pull",
                    params={"entity_type": etype, "since": since},
                    headers=_headers(token),
                    timeout=30,
                )
                resp.raise_for_status()
                records = resp.json().get("records", [])

                col_names = {c.key for c in sa_inspect(model).columns}

                applied = 0
                for rec in records:
                    existing = db.get(model, rec["id"])
                    if existing is None:
                        fields = {k: v for k, v in rec.items() if k in col_names}
                        obj = model(**fields)
                        db.add(obj)
                        applied += 1
                    else:
                        remote_ts = _parse_dt(rec.get("updated_at"))
                        local_ts  = existing.updated_at
                        if local_ts and local_ts.tzinfo is None:
                            local_ts = local_ts.replace(tzinfo=timezone.utc)
                        if remote_ts and (not local_ts or remote_ts > local_ts):
                            for k, v in rec.items():
                                if k in col_names and k != "id":
                                    setattr(existing, k, v)
                            applied += 1

                summary["pulled"][etype] = applied
                state.records_pulled += applied
                state.last_pull_at = datetime.now(timezone.utc)
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


# ── Sync status ──────────────────────────────────────────────────────────────

def get_sync_status(db: Session) -> dict:
    url, token, enabled = _load_sync_credentials()
    states = db.query(SyncState).all()
    return {
        "cloud_url":      url,
        "configured":     bool(url and token),
        "enabled":        enabled,
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
