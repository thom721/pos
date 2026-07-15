from sqlalchemy import create_engine, event
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from api.core.config import settings, get_database_url

SQLALCHEMY_DATABASE_URL = get_database_url()

_connect_args = {}
if settings.DB_TYPE == "sqlite":
    _connect_args = {"check_same_thread": False}

_pool_kwargs = {}
if settings.DB_TYPE == "mysql":
    _pool_kwargs = {"pool_pre_ping": True, "pool_recycle": 3600}

engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args=_connect_args, **_pool_kwargs)

if settings.DB_TYPE == "sqlite":
    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_conn, _):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
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


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
