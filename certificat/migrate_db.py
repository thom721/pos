#!/usr/bin/env python3
"""
migrate_db.py — Migration SQLite <-> MySQL pour POS Connect
============================================================
Usage :
    python migrate_db.py sqlite-to-mysql  [options]
    python migrate_db.py mysql-to-sqlite  [options]

Options :
    --ini PATH        pos_server.ini  (défaut : C:\\ProgramData\\POS_Connect\\pos_server.ini)
    --sqlite PATH     Fichier .db SQLite (défaut : lu depuis INI ou pos_data.db)
    --mysql-host H    Hôte MySQL    (défaut : INI)
    --mysql-port P    Port MySQL    (défaut : INI)
    --mysql-db   D    Nom base      (défaut : INI)
    --mysql-user U    Utilisateur   (défaut : INI)
    --mysql-pass P    Mot de passe  (défaut : INI)
    --no-backup       Sauter le backup (déconseillé)
    --dry-run         Simuler sans écrire
    --batch  N        Lignes par batch INSERT (défaut : 500)
"""

import argparse
import configparser
import datetime
import os
import shutil
import subprocess
import sys
import urllib.parse
from pathlib import Path

# ---------------------------------------------------------------------------
# Dépendances runtime (sqlalchemy, pymysql embarqués dans le bundle Nuitka)
# ---------------------------------------------------------------------------
try:
    import sqlalchemy as sa
    from sqlalchemy import inspect as sa_inspect, text
except ImportError:
    sys.exit("ERREUR : SQLAlchemy n'est pas installé. pip install sqlalchemy pymysql")

# Tables à ignorer (données transientes ou spécifiques à un moteur)
_SKIP_TABLES = {
    "alembic_version",       # version schéma — réinitialisé après migration
    "offline_sync_queue",    # file d'attente locale, transiente
}

# Tables dont on vide la destination avant de copier (pas d'UPSERT)
# On détecte automatiquement l'ordre par les FK, mais ces tables sont
# vidées en sens inverse (enfants avant parents) puis remplies parents→enfants.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    print(f"[migrate] {msg}", flush=True)


def err(msg: str) -> None:
    print(f"[ERREUR]  {msg}", file=sys.stderr, flush=True)


def die(msg: str) -> None:
    err(msg)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Lecture pos_server.ini
# ---------------------------------------------------------------------------

def _read_ini(ini_path: str) -> dict:
    cfg = configparser.ConfigParser()
    cfg.read(ini_path, encoding="utf-8")
    db = cfg["database"] if "database" in cfg else {}
    return {
        "type":     db.get("type",     "mysql"),
        "host":     db.get("host",     "127.0.0.1"),
        "port":     int(db.get("port", "3307")),
        "name":     db.get("name",     "pos_db"),
        "user":     db.get("user",     "pos_user"),
        "password": db.get("password", ""),
        "path":     db.get("path",     "C:\\ProgramData\\POS_Connect\\pos_data.db"),
    }


def _default_ini() -> str:
    if sys.platform == "win32":
        return r"C:\ProgramData\POS_Connect\pos_server.ini"
    return "/etc/pos_connect/pos_server.ini"


# ---------------------------------------------------------------------------
# Construction des URLs SQLAlchemy
# ---------------------------------------------------------------------------

def _sqlite_url(path: str) -> str:
    return f"sqlite:///{path}"


def _mysql_url(host: str, port: int, db: str, user: str, password: str) -> str:
    pw = urllib.parse.quote_plus(password)
    return f"mysql+pymysql://{user}:{pw}@{host}:{port}/{db}?charset=utf8mb4"


# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

def _backup_sqlite(sqlite_path: str) -> str:
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = f"{sqlite_path}.backup_{ts}"
    shutil.copy2(sqlite_path, backup)
    log(f"Backup SQLite → {backup}")
    return backup


def _backup_mysql(host: str, port: int, db: str, user: str, password: str,
                  mysqldump_exe: str) -> str:
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = Path(os.environ.get("TEMP", "/tmp")) / f"pos_mysql_backup_{ts}.sql"
    cmd = [
        mysqldump_exe, f"--host={host}", f"--port={port}",
        f"--user={user}", f"--password={password}",
        "--single-transaction", "--routines", "--triggers",
        db, f"--result-file={out}",
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        log(f"Backup MySQL → {out}")
        return str(out)
    except FileNotFoundError:
        log("mysqldump introuvable — backup MySQL ignoré (continuez à vos risques)")
        return ""
    except subprocess.CalledProcessError as exc:
        log(f"mysqldump a échoué ({exc.returncode}) — backup MySQL ignoré")
        return ""


def _find_mysqldump() -> str:
    """Cherche mysqldump dans les emplacements courants (Windows + Linux)."""
    candidates = [
        "mysqldump",
        r"C:\ProgramData\POS_Connect\mysql\bin\mysqldump.exe",
        r"C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe",
        "/usr/bin/mysqldump",
        "/usr/local/bin/mysqldump",
    ]
    for c in candidates:
        if shutil.which(c):
            return c
        if os.path.isfile(c):
            return c
    return "mysqldump"


# ---------------------------------------------------------------------------
# Ordre des tables (topologie FK)
# ---------------------------------------------------------------------------

def _sorted_tables(meta: sa.MetaData) -> list:
    """Retourne les tables dans l'ordre parents→enfants (insert order)."""
    return list(meta.sorted_tables)


# ---------------------------------------------------------------------------
# Conversion de valeurs selon le sens de la migration
# ---------------------------------------------------------------------------

def _coerce_sqlite_to_mysql(val):
    """Adapte une valeur lue depuis SQLite avant INSERT dans MySQL."""
    if isinstance(val, str):
        # Datetime stocké comme texte dans SQLite — parser proprement
        for fmt in (
            "%Y-%m-%d %H:%M:%S.%f",
            "%Y-%m-%d %H:%M:%S",
            "%Y-%m-%dT%H:%M:%S.%f",
            "%Y-%m-%dT%H:%M:%S",
        ):
            try:
                dt = datetime.datetime.strptime(val, fmt)
                return dt.replace(tzinfo=None)  # MySQL DATETIME sans tz
            except ValueError:
                pass
    if isinstance(val, datetime.datetime):
        return val.replace(tzinfo=None)
    return val


def _coerce_mysql_to_sqlite(val):
    """Adapte une valeur lue depuis MySQL avant INSERT dans SQLite."""
    if isinstance(val, datetime.datetime):
        return val.replace(tzinfo=None)  # SQLite ne gère pas les tz
    if isinstance(val, datetime.date) and not isinstance(val, datetime.datetime):
        return val.isoformat()
    return val


# ---------------------------------------------------------------------------
# Copie d'une table
# ---------------------------------------------------------------------------

def _copy_table(
    src_conn,
    dst_conn,
    table: sa.Table,
    coerce_fn,
    batch_size: int,
    dry_run: bool,
) -> int:
    """Lit les lignes depuis src, insère dans dst. Retourne le nombre de lignes."""
    rows = src_conn.execute(table.select()).mappings().all()
    if not rows:
        return 0

    total = len(rows)
    if dry_run:
        log(f"  [dry-run] {table.name} : {total} lignes (non écrites)")
        return total

    # Vider la table de destination avant d'insérer (enfants déjà vidés en amont)
    dst_conn.execute(table.delete())

    inserted = 0
    for i in range(0, total, batch_size):
        chunk = rows[i: i + batch_size]
        coerced = [{k: coerce_fn(v) for k, v in row.items()} for row in chunk]
        dst_conn.execute(table.insert(), coerced)
        inserted += len(chunk)

    return inserted


# ---------------------------------------------------------------------------
# Migration principale
# ---------------------------------------------------------------------------

def _disable_fk(conn, dialect: str) -> None:
    if dialect == "mysql":
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 0"))
    elif dialect == "sqlite":
        conn.execute(text("PRAGMA foreign_keys = OFF"))


def _enable_fk(conn, dialect: str) -> None:
    if dialect == "mysql":
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 1"))
    elif dialect == "sqlite":
        conn.execute(text("PRAGMA foreign_keys = ON"))


def migrate(
    src_url: str,
    dst_url: str,
    coerce_fn,
    batch_size: int,
    dry_run: bool,
    create_schema: bool = True,
) -> None:
    """
    Copie les données de src_url vers dst_url.
    Si create_schema=True, crée les tables absentes dans dst via les modèles.
    """
    log(f"Connexion source : {src_url.split('@')[-1] if '@' in src_url else src_url}")
    log(f"Connexion dest   : {dst_url.split('@')[-1] if '@' in dst_url else dst_url}")

    # -- Connexions --
    src_engine = sa.create_engine(src_url)
    dst_engine = sa.create_engine(dst_url)

    # -- Schéma destination : créer les tables manquantes --
    if create_schema:
        log("Synchronisation du schéma destination...")
        try:
            _import_models()
            from api.models.base import Base  # type: ignore
            Base.metadata.create_all(dst_engine, checkfirst=True)
        except Exception as exc:
            log(f"  (schéma auto ignoré — {exc})")

    # -- Réflexion sur la source --
    src_meta = sa.MetaData()
    with src_engine.connect() as src_conn:
        src_meta.reflect(bind=src_engine)

    tables = [t for t in _sorted_tables(src_meta) if t.name not in _SKIP_TABLES]
    dst_dialect = dst_engine.dialect.name

    log(f"{len(tables)} tables à migrer (ordre FK respecté)")

    with src_engine.connect() as src_conn, dst_engine.connect() as dst_conn:
        _disable_fk(dst_conn, dst_dialect)
        try:
            total_rows = 0
            errors: list[str] = []

            for table in tables:
                # Vérifier que la table existe en destination
                dst_inspector = sa_inspect(dst_engine)
                if table.name not in dst_inspector.get_table_names():
                    log(f"  SKIP {table.name} (absente en destination)")
                    continue

                # Refléter la table destination pour avoir les bonnes colonnes
                dst_meta_t = sa.MetaData()
                dst_meta_t.reflect(bind=dst_engine, only=[table.name])
                dst_table = dst_meta_t.tables[table.name]

                try:
                    n = _copy_table(src_conn, dst_conn, dst_table, coerce_fn,
                                    batch_size, dry_run)
                    dst_conn.commit()
                    log(f"  OK  {table.name:<40} {n:>6} lignes")
                    total_rows += n
                except Exception as exc:
                    dst_conn.rollback()
                    msg = f"  ERR {table.name}: {exc}"
                    log(msg)
                    errors.append(msg)

        finally:
            _enable_fk(dst_conn, dst_dialect)

    log("")
    log(f"Migration terminée : {total_rows} lignes copiées")
    if errors:
        log(f"{len(errors)} erreur(s) :")
        for e in errors:
            log(f"  {e}")
        sys.exit(1)
    else:
        log("Succès.")


def _import_models() -> None:
    """Importe tous les modèles pour peupler Base.metadata."""
    import importlib, glob
    models_dir = Path(__file__).parent.parent / "api" / "models"
    for f in sorted(glob.glob(str(models_dir / "*.py"))):
        mod = Path(f).stem
        if mod.startswith("_") or mod == "base":
            continue
        try:
            importlib.import_module(f"api.models.{mod}")
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Mise à jour de pos_server.ini
# ---------------------------------------------------------------------------

def _rewrite_ini_type(ini_path: str, new_type: str) -> None:
    if not os.path.isfile(ini_path):
        return
    content = Path(ini_path).read_text(encoding="utf-8")
    import re
    content = re.sub(
        r"(?m)^(\s*type\s*=\s*).*$",
        f"\\g<1>{new_type}",
        content,
    )
    Path(ini_path).write_text(content, encoding="utf-8")
    log(f"pos_server.ini mis à jour : type = {new_type}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Migration SQLite ↔ MySQL pour POS Connect",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("direction", choices=["sqlite-to-mysql", "mysql-to-sqlite"])
    parser.add_argument("--ini",        default=_default_ini())
    parser.add_argument("--sqlite",     default=None)
    parser.add_argument("--mysql-host", default=None)
    parser.add_argument("--mysql-port", type=int, default=None)
    parser.add_argument("--mysql-db",   default=None)
    parser.add_argument("--mysql-user", default=None)
    parser.add_argument("--mysql-pass", default=None)
    parser.add_argument("--no-backup",  action="store_true")
    parser.add_argument("--dry-run",    action="store_true")
    parser.add_argument("--batch",      type=int, default=500)
    parser.add_argument("--update-ini", action="store_true",
                        help="Réécrire le type dans pos_server.ini après migration")
    args = parser.parse_args()

    # -- Lire INI --
    ini = _read_ini(args.ini) if os.path.isfile(args.ini) else {}

    # -- Paramètres SQLite --
    sqlite_path = args.sqlite or ini.get("path") or "pos_data.db"

    # -- Paramètres MySQL --
    mysql_host = args.mysql_host or ini.get("host", "127.0.0.1")
    mysql_port = args.mysql_port or ini.get("port", 3307)
    mysql_db   = args.mysql_db   or ini.get("name", "pos_db")
    mysql_user = args.mysql_user or ini.get("user", "pos_user")
    mysql_pass = args.mysql_pass or ini.get("password", "")

    # -- Validation --
    if args.direction == "sqlite-to-mysql":
        if not os.path.isfile(sqlite_path):
            die(f"Fichier SQLite introuvable : {sqlite_path}")

        # Backup
        if not args.no_backup and not args.dry_run:
            _backup_sqlite(sqlite_path)

        src_url = _sqlite_url(sqlite_path)
        dst_url = _mysql_url(mysql_host, mysql_port, mysql_db, mysql_user, mysql_pass)
        coerce  = _coerce_sqlite_to_mysql

    else:  # mysql-to-sqlite
        if not args.no_backup and not args.dry_run:
            dump = _find_mysqldump()
            _backup_mysql(mysql_host, mysql_port, mysql_db, mysql_user, mysql_pass, dump)
            if os.path.isfile(sqlite_path):
                _backup_sqlite(sqlite_path)

        src_url = _mysql_url(mysql_host, mysql_port, mysql_db, mysql_user, mysql_pass)
        dst_url = _sqlite_url(sqlite_path)
        coerce  = _coerce_mysql_to_sqlite

    if args.dry_run:
        log("MODE DRY-RUN — aucune écriture ne sera effectuée")

    migrate(
        src_url=src_url,
        dst_url=dst_url,
        coerce_fn=coerce,
        batch_size=args.batch,
        dry_run=args.dry_run,
    )

    if args.update_ini and not args.dry_run:
        new_type = "mysql" if args.direction == "sqlite-to-mysql" else "sqlite"
        _rewrite_ini_type(args.ini, new_type)


if __name__ == "__main__":
    main()
