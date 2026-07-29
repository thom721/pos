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


def coerce_enums(model, record: dict) -> dict:
    """Convertit les strings brutes reçues sur le fil (format API `.value`, ex:
    StockType.in_ → "in") en instances du Python Enum correspondant, pour les
    colonnes Enum du modèle.

    Nécessaire car un modèle Enum SQLAlchemy peut être configuré pour stocker
    soit le NOM du membre (défaut, ex: "in_"), soit sa VALEUR (via
    values_callable, ex: Sale.status → "PAID") — la représentation exposée par
    l'API est toujours `.value`, mais le label DB attendu par `model(**clean)`
    dépend de cette config par colonne. Assigner directement la string brute
    au constructeur du modèle contourne la conversion normale de SQLAlchemy
    et peut échouer (ex: MySQL "Data truncated for column 'type'") si le label
    DB réel ne correspond pas à la string reçue. Reconvertir en membre Enum ici
    laisse SQLAlchemy dériver le bon label au flush, comme partout ailleurs
    dans le code où l'on assigne StockType.in_ / SaleStatus.paid directement.
    """
    from sqlalchemy import inspect as _sa_inspect

    try:
        mapper = _sa_inspect(model)
    except Exception:
        return record

    result = dict(record)
    for col in mapper.columns:
        key = col.key
        if key not in result:
            continue
        v = result[key]
        if not isinstance(v, str):
            continue
        enum_class = getattr(col.type, "enum_class", None)
        if enum_class is None:
            continue
        try:
            result[key] = enum_class(v)
        except ValueError:
            try:
                result[key] = enum_class[v]
            except KeyError:
                pass  # valeur invalide — laissée telle quelle, échouera comme avant
    return result
