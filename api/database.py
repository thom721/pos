from sqlalchemy import create_engine, event
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from api.core.config import settings, get_database_url

SQLALCHEMY_DATABASE_URL = get_database_url()

_connect_args = {}
if settings.DB_TYPE == "sqlite":
    # timeout=15 : sqlite3 attend 15 s avant SQLITE_BUSY (évite "database is locked"
    # sur écritures concurrentes sync ↔ requêtes API).
    _connect_args = {"check_same_thread": False, "timeout": 15}
elif settings.DB_TYPE == "mysql":
    # connect_timeout évite que PyMySQL bloque indéfiniment si MySQL ne répond pas
    _connect_args = {"connect_timeout": 10}

_pool_kwargs = {}
if settings.DB_TYPE == "mysql":
    _pool_kwargs = {
        "pool_pre_ping":  True,
        "pool_recycle":   3600,
        "pool_timeout":   10,   # attente max pour obtenir une conn du pool
        "pool_size":      5,
        "max_overflow":   10,
    }

engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args=_connect_args, **_pool_kwargs)

if settings.DB_TYPE == "sqlite":
    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_conn, _):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA busy_timeout=15000")   # 15 s avant SQLITE_BUSY
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

elif settings.DB_TYPE == "mysql":
    @event.listens_for(engine, "connect")
    def _set_mysql_utc(dbapi_conn, _):
        # Force UTC so updated_at comparisons in sync are timezone-consistent
        cursor = dbapi_conn.cursor()
        cursor.execute("SET time_zone='+00:00'")
        cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# ── Safety net : convertit les strings ISO → datetime naïf avant tout flush
# SQLite. Fonctionne même quand le fallback SQLite est activé au runtime
# (main.py remplace engine après l'import).  Aucun impact sur MySQL.
from datetime import datetime as _dt_cls
from sqlalchemy import DateTime as _DT, inspect as _sa_inspect
from sqlalchemy.orm import Session as _Session

@event.listens_for(_Session, "before_flush")
def _coerce_dt_strings_sqlite(session, flush_context, instances):
    # settings.DB_TYPE est mis à jour dynamiquement si le fallback SQLite s'active
    if settings.DB_TYPE != "sqlite":
        return
    def _fix(obj):
        try:
            for col in _sa_inspect(type(obj)).columns:
                if isinstance(col.type, _DT):
                    val = getattr(obj, col.key, None)
                    if isinstance(val, str):
                        try:
                            setattr(obj, col.key,
                                    _dt_cls.fromisoformat(val).replace(tzinfo=None))
                        except Exception:
                            pass
        except Exception:
            pass
    for obj in list(session.new) + list(session.dirty):
        _fix(obj)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
