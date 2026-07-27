"""
Utilitaire de conversion datetime pour compatibilité SQLite/MySQL.

SQLite exige des objets datetime Python naïfs (sans tzinfo).
MySQL accepte indifféremment strings ISO et datetime objects.
Ce module fournit une conversion uniforme utilisée partout où des données
provenant de l'API cloud (strings ISO) sont écrites en base locale.
"""
from __future__ import annotations
from datetime import datetime
from zoneinfo import ZoneInfo

HAITI_TZ = ZoneInfo("America/Port-au-Prince")


def now_local() -> datetime:
    """Heure actuelle naïve en heure locale Haiti (America/Port-au-Prince).

    Utilisé pour tous les champs DateTime métier (created_at/updated_at,
    dates de trial/abonnement, y compris celles ensuite chiffrées en Fernet).
    """
    return datetime.now(HAITI_TZ).replace(tzinfo=None)


def parse_dt(value: str | None) -> datetime | None:
    """Parse une string ISO en datetime naïf (heure locale Haiti).

    Les strings sans offset représentent déjà l'heure locale Haiti — on ne
    réattache plus tzinfo=UTC ici. Les strings avec offset (legacy) sont
    converties vers l'heure locale Haiti puis dénudées de leur tzinfo.
    """
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value)
        if dt.tzinfo is not None:
            dt = dt.astimezone(HAITI_TZ).replace(tzinfo=None)
        return dt
    except Exception:
        return None


def coerce_datetimes(record: dict, *, strip_tz: bool = True) -> dict:
    """Convertit les strings ISO des champs *_at / *_date en datetime Python naïfs."""
    result: dict = {}
    for k, v in record.items():
        if isinstance(v, str) and (k.endswith("_at") or k.endswith("_date")):
            parsed = parse_dt(v)
            if parsed is not None:
                v = parsed
        result[k] = v
    return result
