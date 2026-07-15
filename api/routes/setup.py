"""
First-run setup endpoint.
Called once by the installer to:
  1. Test DB connectivity
  2. Test MySQL credentials (if applicable)
  3. Create the initial admin account
  4. Write pos_server.ini

After initial setup, the /setup/init endpoint is permanently disabled.
"""
import os
import subprocess
import platform
import shutil
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import text

from api.database import get_db, engine, Base
from api.models.User import User
from api.models.Tenant import Tenant
from api.services.auth import get_password_hash
from api.core.config import settings, write_ini_config

router = APIRouter(prefix="/setup", tags=["Setup"])


# ── Schemas ────────────────────────────────────────────────────────────────────

class DbTestRequest(BaseModel):
    db_type: str          # "mysql" | "sqlite"
    host: str = "localhost"
    port: int = 3306
    name: str = "pos_db"
    user: str = "root"
    password: str = ""
    path: str = "./pos_data.db"


class InitRequest(BaseModel):
    # DB config
    db_type: str
    host: str = "localhost"
    port: int = 3306
    name: str = "pos_db"
    user: str = "root"
    password: str = ""
    path: str = "./pos_data.db"
    # Admin account
    fname: str
    lname: str
    username: str
    email: str
    phone: str
    admin_password: str
    # Server config
    server_host: str = "0.0.0.0"
    server_port: int = 9003
    secret_key: str = ""


class ConnectTenantRequest(BaseModel):
    """Wizard step: link local installation to a cloud tenant account."""
    cloud_url: str
    email: str
    password: str
    # DB config — to build engine targeting the configured database
    db_type: str
    host: str = "localhost"
    port: int = 3306
    name: str = "pos_db"
    user: str = "root"
    db_password: str = ""
    path: str = "./pos_data.db"
    server_host: str = "0.0.0.0"
    server_port: int = 9003


class MigrateRequest(BaseModel):
    """Switch from MySQL ↔ SQLite (admin credentials required)."""
    username: str
    password: str
    target_db_type: str       # "mysql" | "sqlite"
    host: str = "localhost"
    port: int = 3306
    name: str = "pos_db"
    user: str = "root"
    db_password: str = ""
    path: str = "./pos_data.db"


# ── Helpers ────────────────────────────────────────────────────────────────────

def _is_setup_done(db: Session) -> bool:
    try:
        return db.query(User).count() > 0
    except Exception:
        return False


def _test_mysql(host, port, name, user, password) -> str | None:
    """
    Teste les credentials MySQL sans spécifier de base de données.
    Évite l'erreur 1049 (Unknown database) si pos_db n'existe pas encore.
    """
    import urllib.parse
    try:
        from sqlalchemy import create_engine as _ce
        pw = urllib.parse.quote_plus(password)
        # Connexion sans base — teste uniquement host/user/password
        url = f"mysql+pymysql://{user}:{pw}@{host}:{port}/"
        eng = _ce(url, connect_args={"connect_timeout": 5})
        with eng.connect() as c:
            c.execute(text("SELECT 1"))
        eng.dispose()
        return None
    except Exception as e:
        return str(e)


def _auto_fix_mysql_socket(user: str, new_password: str) -> bool:
    """
    Sur Debian/Ubuntu, MySQL root utilise auth_socket par défaut (pas de mot de passe).
    On tente de se connecter via socket Unix puis d'activer l'auth par mot de passe.
    Retourne True si la configuration a réussi.
    """
    import pymysql

    # 1. Tentative via socket Unix (fonctionne si l'OS user == MySQL user, ex: root)
    socket_paths = [
        "/var/run/mysqld/mysqld.sock",
        "/tmp/mysql.sock",
        "/var/lib/mysql/mysql.sock",
    ]
    for sock in socket_paths:
        if not os.path.exists(sock):
            continue
        try:
            conn = pymysql.connect(
                unix_socket=sock, user=user, password="",
                charset="utf8mb4", connect_timeout=5,
            )
            with conn.cursor() as cur:
                # Syntaxe universelle MySQL + MariaDB
                cur.execute(
                    "ALTER USER %s@'localhost' IDENTIFIED BY %s",
                    (user, new_password),
                )
                cur.execute("FLUSH PRIVILEGES")
            conn.commit()
            conn.close()
            return True
        except Exception:
            continue

    # 2. Tentative via subprocess mysql sans mot de passe (auth_socket via l'OS user courant)
    try:
        # IDENTIFIED BY fonctionne sur MySQL et MariaDB
        sql = (
            f"ALTER USER '{user}'@'localhost' "
            f"IDENTIFIED BY '{new_password}'; "
            f"FLUSH PRIVILEGES;"
        )
        r = subprocess.run(
            ["mysql", "-u", user, "-e", sql],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0:
            return True
    except Exception:
        pass

    # 3. Tentative via sudo -n (non-interactif, fonctionne si NOPASSWD configuré)
    try:
        r = subprocess.run(
            ["sudo", "-n", "mysql", "-u", user, "-e", sql],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0:
            return True
    except Exception:
        pass

    return False


def _detect_mysql() -> dict:
    """Check if MySQL is installed on this machine."""
    cmd = shutil.which("mysql")
    if not cmd:
        return {"installed": False}
    try:
        r = subprocess.run(
            ["mysql", "--version"],
            capture_output=True, text=True, timeout=5
        )
        return {"installed": True, "version": r.stdout.strip()}
    except Exception:
        return {"installed": False}


# ── Routes ─────────────────────────────────────────────────────────────────────

@router.get("/health")
def health(db: Session = Depends(get_db)):
    """Quick health check — used by installer and launcher."""
    try:
        db.execute(text("SELECT 1"))
        setup_done = _is_setup_done(db)
        return {
            "status": "ok",
            "db_type": settings.DB_TYPE,
            "setup_done": setup_done,
        }
    except Exception as e:
        raise HTTPException(503, f"DB indisponible: {e}")


@router.get("/detect-mysql")
def detect_mysql():
    """Detect if MySQL is installed and return installation instructions if not."""
    result = _detect_mysql()
    if not result["installed"]:
        os_name = platform.system()
        instructions = {
            "Windows": (
                "1. Télécharger MySQL Community Server : https://dev.mysql.com/downloads/mysql/\n"
                "2. Exécuter l'installateur .msi\n"
                "3. Choisir 'Server only'\n"
                "4. Configurer le mot de passe root\n"
                "5. Relancer ce wizard"
            ),
            "Darwin": (
                "Via Homebrew (recommandé) :\n"
                "  brew install mysql\n"
                "  brew services start mysql\n"
                "  mysql_secure_installation\n\n"
                "Ou télécharger depuis : https://dev.mysql.com/downloads/mysql/"
            ),
            "Linux": (
                "Ubuntu/Debian :\n"
                "  sudo apt update && sudo apt install mysql-server\n"
                "  sudo systemctl start mysql\n"
                "  sudo mysql_secure_installation\n\n"
                "CentOS/RHEL :\n"
                "  sudo yum install mysql-server\n"
                "  sudo systemctl start mysqld"
            ),
        }
        return {
            "installed": False,
            "os": os_name,
            "instructions": instructions.get(os_name, "Voir https://dev.mysql.com/downloads/mysql/"),
        }
    return result


@router.post("/test-db")
def test_db_connection(data: DbTestRequest):
    """Test database connectivity before saving config."""
    if data.db_type == "sqlite":
        # Écriture anticipée de pos_server.ini pour que le prochain démarrage soit correct
        write_ini_config({
            "type": "sqlite", "path": data.path,
        })
        return {"ok": True, "message": "SQLite: aucune connexion réseau requise."}

    err = _test_mysql(data.host, data.port, data.name, data.user, data.password)
    if err is None:
        # Écriture anticipée de pos_server.ini dès que les credentials sont validés
        write_ini_config({
            "type": data.db_type, "host": data.host, "port": data.port,
            "name": data.name, "user": data.user, "password": data.password,
        })
        return {"ok": True, "message": "Connexion MySQL réussie."}

    # Sur Debian/Ubuntu, MySQL root utilise auth_socket — tentative de configuration automatique
    is_access_denied = "1045" in err or "Access denied" in err.lower()
    if is_access_denied and data.host in ("localhost", "127.0.0.1"):
        fixed = _auto_fix_mysql_socket(data.user, data.password)
        if fixed:
            err2 = _test_mysql(data.host, data.port, data.name, data.user, data.password)
            if err2 is None:
                write_ini_config({
                    "type": data.db_type, "host": data.host, "port": data.port,
                    "name": data.name, "user": data.user, "password": data.password,
                })
                return {
                    "ok": True,
                    "message": f"Connexion réussie. Authentification MySQL configurée automatiquement pour '{data.user}'.",
                    "auto_configured": True,
                }

    raise HTTPException(400, f"Connexion MySQL échouée: {err}")


@router.post("/create-db")
def create_database(data: DbTestRequest):
    """Create the database schema using the credentials from the request."""
    try:
        import urllib.parse
        from sqlalchemy import create_engine as _ce

        if data.db_type == "mysql":
            pw = urllib.parse.quote_plus(data.password)
            # 1. Créer la base si elle n'existe pas
            root_url = f"mysql+pymysql://{data.user}:{pw}@{data.host}:{data.port}"
            eng_root = _ce(root_url, connect_args={"connect_timeout": 10})
            with eng_root.connect() as c:
                c.execute(text(
                    f"CREATE DATABASE IF NOT EXISTS `{data.name}` "
                    f"CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
                ))
            eng_root.dispose()
            # 2. Créer les tables dans la bonne base avec le bon moteur
            target_url = f"mysql+pymysql://{data.user}:{pw}@{data.host}:{data.port}/{data.name}"
            target_eng = _ce(target_url, connect_args={"connect_timeout": 10})
        else:
            target_eng = _ce(f"sqlite:///{data.path}", connect_args={"check_same_thread": False})

        Base.metadata.create_all(bind=target_eng)
        target_eng.dispose()
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, f"Erreur création base: {e}")


@router.post("/init")
def initial_setup(data: InitRequest):
    """
    One-time setup: write config + create admin account.
    Uses a fresh engine built from request credentials — works even if
    the server started without pos_server.ini.
    """
    import secrets
    import urllib.parse
    from sqlalchemy import create_engine as _ce
    from sqlalchemy.orm import sessionmaker

    # Build engine targeting the configured database
    if data.db_type == "mysql":
        pw = urllib.parse.quote_plus(data.password)
        url = f"mysql+pymysql://{data.user}:{pw}@{data.host}:{data.port}/{data.name}"
        target_eng = _ce(url, connect_args={"connect_timeout": 10})
    else:
        target_eng = _ce(
            f"sqlite:///{data.path}",
            connect_args={"check_same_thread": False},
        )

    TargetSession = sessionmaker(bind=target_eng)
    db = TargetSession()
    try:
        if _is_setup_done(db):
            raise HTTPException(403, "Setup déjà effectué. Endpoint désactivé.")

        if len(data.admin_password) < 8:
            raise HTTPException(400, "Le mot de passe doit contenir au moins 8 caractères.")

        if db.query(User).filter(User.username == data.username).first():
            raise HTTPException(400, "Ce nom d'utilisateur est déjà pris.")

        # Write final pos_server.ini (avec secret_key)
        secret = data.secret_key or secrets.token_hex(32)
        write_ini_config({
            "type":        data.db_type,
            "host":        data.host,
            "port":        str(data.port),
            "name":        data.name,
            "user":        data.user,
            "password":    data.password,
            "path":        data.path,
            "secret_key":  secret,
            "server_host": data.server_host,
            "server_port": str(data.server_port),
        })

        admin = User(
            fname=data.fname,
            lname=data.lname,
            username=data.username,
            email=data.email,
            phone=data.phone,
            address="",
            password=get_password_hash(data.admin_password),
            roles=["admin"],
            permissions=["all"],
            must_change_password=False,
        )
        db.add(admin)
        db.commit()
        return {"ok": True, "message": f"Compte admin '{data.username}' créé avec succès."}
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(500, f"Erreur initialisation: {e}")
    finally:
        db.close()
        target_eng.dispose()


@router.post("/connect-tenant")
def connect_tenant(data: ConnectTenantRequest):
    """
    Wizard finalization step: authenticate against the cloud SaaS, save sync
    config to pos_server.ini, and create the local admin user.
    Called once by the installer (replaces /setup/init for cloud-linked installs).
    """
    import secrets
    import urllib.parse
    import httpx
    from sqlalchemy import create_engine as _ce
    from sqlalchemy.orm import sessionmaker

    cloud_url = data.cloud_url.rstrip("/")

    # ── 1. Validate credentials against cloud ────────────────────────────────
    try:
        resp = httpx.post(
            f"{cloud_url}/api/sync/token",
            json={"owner_email": data.email, "password": data.password},
            timeout=15,
        )
        resp.raise_for_status()
        body = resp.json()
        sync_token   = body.get("sync_token") or body.get("token") or body.get("access_token")
        tenant_type  = body.get("tenant_type", "shared")
        self_hosted_url = body.get("self_hosted_url") or None
    except httpx.HTTPStatusError as exc:
        code = exc.response.status_code
        if code in (401, 403):
            raise HTTPException(403, "Identifiants incorrects ou compte inactif sur le cloud")
        raise HTTPException(502, f"Erreur serveur cloud ({code})")
    except Exception as exc:
        raise HTTPException(502, f"Impossible de joindre le serveur cloud: {exc}")

    if not sync_token:
        raise HTTPException(502, "Réponse inattendue du serveur cloud (token manquant)")

    # ── 2. Write pos_server.ini (db + server + sync config) ──────────────────
    # Self-hosted: données business → self_hosted_url, billing → cloud_url
    # Shared:      données business → cloud_url,       billing → cloud_url
    data_sync_url = (self_hosted_url.rstrip("/") if self_hosted_url else cloud_url) \
        if tenant_type == "selfhosted" else cloud_url

    cloud_tenant_id = body.get("tenant_id") or ""
    cloud_user_id   = body.get("user_id")   or ""

    secret = secrets.token_hex(32)
    write_ini_config({
        "type":               data.db_type,
        "host":               data.host,
        "port":               str(data.port),
        "name":               data.name,
        "user":               data.user,
        "password":           data.db_password,
        "path":               data.path,
        "secret_key":         secret,
        "server_host":        data.server_host,
        "server_port":        str(data.server_port),
        "cloud_sync_url":     data_sync_url,
        "cloud_sync_token":   sync_token,
        "cloud_sync_enabled": "true",
        "billing_url":        cloud_url,
        "cloud_tenant_id":    cloud_tenant_id,
        "cloud_owner_email":  data.email,
    })

    can_manage = body.get("can_manage_tenants", False)

    # ── 3. Create local admin user in DB ─────────────────────────────────────
    # Regular tenants (can_manage_tenants=False) only need their own admin account.
    # They don't need a platform-level superadmin.
    if data.db_type == "mysql":
        pw = urllib.parse.quote_plus(data.db_password)
        db_url = f"mysql+pymysql://{data.user}:{pw}@{data.host}:{data.port}/{data.name}"
        target_eng = _ce(db_url, connect_args={"connect_timeout": 10})
    else:
        target_eng = _ce(
            f"sqlite:///{data.path}",
            connect_args={"check_same_thread": False},
        )

    # Make phone nullable on the target DB (MySQL only, safe no-op if already nullable)
    if data.db_type == "mysql":
        try:
            with target_eng.connect() as _conn:
                _conn.execute(
                    __import__("sqlalchemy").text(
                        "ALTER TABLE users MODIFY COLUMN phone VARCHAR(255) NULL"
                    )
                )
                _conn.commit()
        except Exception:
            pass

    Session = sessionmaker(bind=target_eng)
    db = Session()
    try:
        # ── Ensure __local__ tenant exists in target DB with the cloud UUID ─────
        # Using the cloud UUID avoids FK conflicts when pulling cloud records:
        # pulled records already carry the correct tenant_id and need no substitution.
        business_name = body.get("business_name", "") or data.email.split("@")[0]

        # Try to find an existing tenant that already has the cloud UUID
        local_tenant = (
            db.query(Tenant).filter(Tenant.id == cloud_tenant_id).first()
            if cloud_tenant_id else None
        )
        if not local_tenant:
            local_tenant = db.query(Tenant).filter(Tenant.slug == "__local__").first()

        if not local_tenant:
            # Fresh DB — create with the cloud UUID directly
            kwargs = dict(
                slug="__local__",
                business_name=business_name,
                owner_email=data.email,
                status="local",
                is_local=True,
            )
            if cloud_tenant_id:
                kwargs["id"] = cloud_tenant_id
            local_tenant = Tenant(**kwargs)
            db.add(local_tenant)
            db.flush()
        elif cloud_tenant_id and local_tenant.id != cloud_tenant_id:
            # Tenant exists with wrong UUID — realign to cloud UUID.
            # Disable FK checks, update primary key, update all child rows, re-enable.
            old_tid = local_tenant.id
            _sa_text = __import__("sqlalchemy").text
            if data.db_type == "mysql":
                db.execute(_sa_text("SET FOREIGN_KEY_CHECKS=0"))
            db.execute(
                _sa_text("UPDATE tenants SET id = :new WHERE id = :old"),
                {"new": cloud_tenant_id, "old": old_tid},
            )
            for _tbl in [
                "users", "categories", "suppliers", "products", "customers",
                "sales", "sale_items", "purchases", "purchase_items",
                "purchase_receipts", "purchase_receipt_items",
                "payments", "stock_movements", "debts", "return_records",
                "inventory_records", "app_config", "proformas", "proforma_items",
                "invoices", "invoice_items", "employee_profiles",
                "payroll_periods", "payroll_entries", "roles", "pos_registers",
            ]:
                try:
                    db.execute(
                        _sa_text(f"UPDATE `{_tbl}` SET tenant_id = :new WHERE tenant_id = :old"),
                        {"new": cloud_tenant_id, "old": old_tid},
                    )
                except Exception:
                    pass
            if data.db_type == "mysql":
                db.execute(_sa_text("SET FOREIGN_KEY_CHECKS=1"))
            db.flush()

        local_tid = cloud_tenant_id or local_tenant.id

        existing = db.query(User).filter(User.email == data.email).first()
        if existing:
            # Update password + ensure tenant_id is set
            existing.password = get_password_hash(data.password)
            existing.must_change_password = False
            if not existing.tenant_id:
                existing.tenant_id = local_tid

            # Align local user UUID with cloud UUID (avoids duplicate insert on first pull)
            if cloud_user_id and existing.id != cloud_user_id:
                _sa_text = __import__("sqlalchemy").text
                old_uid = existing.id
                _user_fk_cols = [
                    ("sales",             "user_id"),
                    ("purchases",         "user_id"),
                    ("payments",          "user_id"),
                    ("return_records",    "user_id"),
                    ("stock_movements",   "user_id"),
                    ("proformas",         "user_id"),
                    ("inventory_records", "user_id"),
                    ("invoices",          "user_id"),
                    ("employee_profiles", "user_id"),
                    ("payroll_periods",   "created_by"),
                    ("payroll_entries",   "employee_id"),
                    ("cashier_sessions",  "cashier_id"),
                    ("employee_loans",    "employee_id"),
                    ("employee_loans",    "approved_by"),
                    ("employee_loans",    "created_by"),
                ]
                if data.db_type == "mysql":
                    db.execute(_sa_text("SET FOREIGN_KEY_CHECKS=0"))
                db.execute(
                    _sa_text("UPDATE users SET id = :new WHERE id = :old"),
                    {"new": cloud_user_id, "old": old_uid},
                )
                for _tbl, _col in _user_fk_cols:
                    try:
                        db.execute(
                            _sa_text(f"UPDATE `{_tbl}` SET `{_col}` = :new WHERE `{_col}` = :old"),
                            {"new": cloud_user_id, "old": old_uid},
                        )
                    except Exception:
                        pass
                if data.db_type == "mysql":
                    db.execute(_sa_text("SET FOREIGN_KEY_CHECKS=1"))
                db.flush()

            db.commit()
            return {"ok": True, "message": "Compte déjà lié — mot de passe mis à jour."}

        # Use business_name from cloud response for the user's display name
        parts = business_name.split(" ", 1)
        fname = parts[0]
        lname = parts[1] if len(parts) > 1 else ""

        username = body.get("tenant_slug") or data.email.split("@")[0]
        # Ensure username uniqueness
        if db.query(User).filter(User.username == username).first():
            username = f"{username}_{secrets.token_hex(3)}"

        user_kwargs: dict = dict(
            tenant_id=local_tid,
            fname=fname,
            lname=lname,
            username=username,
            email=data.email,
            phone=None,
            password=get_password_hash(data.password),
            roles=["admin"],
            permissions=["all"],
            must_change_password=False,
        )
        if cloud_user_id:
            user_kwargs["id"] = cloud_user_id

        admin = User(**user_kwargs)
        db.add(admin)
        db.commit()
        return {
            "ok":               True,
            "message":          f"Installation liée au compte {data.email}",
            "tenant_type":      tenant_type,
            "can_manage_tenants": can_manage,
            "self_hosted_url":  self_hosted_url,
        }
    except Exception as exc:
        db.rollback()
        raise HTTPException(500, f"Erreur création compte local: {exc}")
    finally:
        db.close()
        target_eng.dispose()


@router.post("/migrate-db")
def migrate_database(data: MigrateRequest, db: Session = Depends(get_db)):
    """
    Switch DB engine. Requires admin credentials.
    WARNING: does NOT migrate existing data automatically.
    """
    from api.services.auth import Auth
    auth = Auth(db)
    user = auth.authenticate_user(data.username, data.password)
    if not user:
        raise HTTPException(401, "Identifiants incorrects.")
    if "admin" not in (user.roles or []) and "all" not in (user.permissions or []):
        raise HTTPException(403, "Accès réservé aux administrateurs.")

    if data.target_db_type == "mysql":
        err = _test_mysql(data.host, data.port, data.name, data.user, data.db_password)
        if err:
            raise HTTPException(400, f"Connexion MySQL échouée: {err}")

    write_ini_config({
        "type":     data.target_db_type,
        "host":     data.host,
        "port":     str(data.port),
        "name":     data.name,
        "user":     data.user,
        "password": data.db_password,
        "path":     data.path,
    })

    return {
        "ok": True,
        "message": (
            f"Configuration mise à jour vers {data.target_db_type}. "
            "Redémarrez le serveur pour appliquer les changements. "
            "⚠️ Les données existantes ne sont PAS migrées automatiquement."
        ),
    }
