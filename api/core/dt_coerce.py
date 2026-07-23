"""
Utilitaire de conversion datetime pour compatibilité SQLite/MySQL.

SQLite exige des objets datetime Python naïfs (sans tzinfo).
MySQL accepte indifféremment strings ISO et datetime objects.
Ce module fournit une conversion uniforme utilisée partout où des données
provenant de l'API cloud (strings ISO) sont écrites en base locale.
"""
from __future__ import annotations
from datetime import datetime, timezone


def parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except Exception:
        return None


def coerce_datetimes(record: dict, *, strip_tz: bool) -> dict:
    """Convertit les strings ISO des champs *_at / *_date en datetime Python.

    strip_tz=True  → supprime tzinfo (requis pour SQLite DateTime naïf)
    strip_tz=False → conserve tzinfo (MySQL accepte les datetime aware)
    """
    result: dict = {}
    for k, v in record.items():
        if isinstance(v, str) and (k.endswith("_at") or k.endswith("_date")):
            parsed = parse_dt(v)
            if parsed is not None:
                v = parsed.replace(tzinfo=None) if strip_tz else parsed
        result[k] = v
    return result
