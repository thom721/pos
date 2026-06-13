"""
First-run setup endpoint.
Called once by the installer to:
  1. Test DB connectivity
  2. Test MySQL credentials (if applicable)
  3. Create the initial admin account
  4. Write pos_server.ini

After initial setup, the /setup/init endpoint is permanently disabled.
"""
import subprocess
import platform
import shutil
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import text

from api.database import get_db, engine, Base
from api.models.User import User
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
    server_port: int = 8002
    secret_key: str = ""


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
        return db.query(User).filter(User.roles.cast(str).contains("admin")).count() > 0
    except Exception:
        return False


def _test_mysql(host, port, name, user, password) -> str | None:
    """Returns None on success, error message on failure."""
    import urllib.parse
    try:
        from sqlalchemy import create_engine as _ce
        pw = urllib.parse.quote_plus(password)
        url = f"mysql+pymysql://{user}:{pw}@{host}:{port}/{name}"
        eng = _ce(url, connect_args={"connect_timeout": 5})
        with eng.connect() as c:
            c.execute(text("SELECT 1"))
        eng.dispose()
        return None
    except Exception as e:
        return str(e)


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
        return {"ok": True, "message": "SQLite: aucune connexion réseau requise."}

    err = _test_mysql(data.host, data.port, data.name, data.user, data.password)
    if err:
        raise HTTPException(400, f"Connexion MySQL échouée: {err}")
    return {"ok": True, "message": "Connexion MySQL réussie."}


@router.post("/create-db")
def create_database(data: DbTestRequest, db: Session = Depends(get_db)):
    """Create the database schema (Alembic migrations)."""
    if _is_setup_done(db):
        raise HTTPException(403, "Setup déjà effectué.")

    try:
        # For MySQL: create DB if it doesn't exist
        if data.db_type == "mysql":
            import urllib.parse
            from sqlalchemy import create_engine as _ce
            pw = urllib.parse.quote_plus(data.password)
            root_url = f"mysql+pymysql://{data.user}:{pw}@{data.host}:{data.port}"
            eng = _ce(root_url)
            with eng.connect() as c:
                c.execute(text(
                    f"CREATE DATABASE IF NOT EXISTS `{data.name}` "
                    f"CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
                ))
            eng.dispose()

        # Create all tables
        Base.metadata.create_all(bind=engine)
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, f"Erreur création base: {e}")


@router.post("/init")
def initial_setup(data: InitRequest, db: Session = Depends(get_db)):
    """
    One-time setup: write config + create admin account.
    Disabled permanently once an admin exists.
    """
    if _is_setup_done(db):
        raise HTTPException(403, "Setup déjà effectué. Endpoint désactivé.")

    # Validate password strength
    if len(data.admin_password) < 8:
        raise HTTPException(400, "Le mot de passe doit contenir au moins 8 caractères.")

    # Check username not taken
    if db.query(User).filter(User.username == data.username).first():
        raise HTTPException(400, "Ce nom d'utilisateur est déjà pris.")

    # Write pos_server.ini
    import secrets
    secret = data.secret_key or secrets.token_hex(32)
    write_ini_config({
        "type":     data.db_type,
        "host":     data.host,
        "port":     str(data.port),
        "name":     data.name,
        "user":     data.user,
        "password": data.password,
        "path":     data.path,
        "secret_key":   secret,
        "server_host":  data.server_host,
        "server_port":  str(data.server_port),
    })

    # Create admin user
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
