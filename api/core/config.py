import os
import configparser
from pathlib import Path
from pydantic.v1 import BaseSettings

# Charger .env en fallback si présent (développement sans pos_server.ini)
try:
    from dotenv import load_dotenv as _load_dotenv
    _load_dotenv(Path(__file__).parent.parent.parent / ".env", override=False)
except ImportError:
    pass


def _find_config_file() -> Path:
    """
    Search for pos_server.ini in order of priority.
    On Windows, ProgramData is writable without admin rights — preferred over
    Program Files which requires elevation.
    """
    candidates = []

    # Windows: C:\ProgramData\POS_Connect\ — lisible/modifiable sans admin
    if os.name == "nt":
        prog_data = Path(os.environ.get("PROGRAMDATA", "C:\\ProgramData"))
        candidates.append(prog_data / "POS_Connect" / "pos_server.ini")

    # Répertoire de l'exécutable (ou du projet en dev)
    candidates.append(
        Path(os.path.dirname(os.path.abspath(__file__))).parent.parent / "pos_server.ini"
    )

    # Répertoire courant
    candidates.append(Path.cwd() / "pos_server.ini")

    # Dossier utilisateur (~/.pos_connect/)
    candidates.append(Path.home() / ".pos_connect" / "pos_server.ini")

    for p in candidates:
        if p.exists():
            return p

    # Chemin d'écriture par défaut : ProgramData sur Windows, sinon répertoire courant
    return candidates[0]


def load_ini_config() -> dict:
    cfg = configparser.ConfigParser()
    ini = _find_config_file()
    if ini.exists():
        cfg.read(ini, encoding="utf-8")
    db = cfg["database"] if "database" in cfg else {}
    srv = cfg["server"] if "server" in cfg else {}
    return {
        "DB_TYPE":     db.get("type",     os.getenv("DB_TYPE",     "mysql")),
        "DB_HOST":     db.get("host",     os.getenv("DB_HOST",     "127.0.0.1")),
        "DB_PORT":     int(db.get("port", os.getenv("DB_PORT",     "3307"))),
        "DB_NAME":     db.get("name",     os.getenv("DB_NAME",     "pos_db")),
        "DB_USER":     db.get("user",     os.getenv("DB_USER",     "pos_user")),
        "DB_PASSWORD": db.get("password", os.getenv("DB_PASSWORD", "")),
        "DB_PATH":     db.get("path",     os.getenv("DB_PATH",     "./pos_data.db")),
        "SECRET_KEY":  srv.get("secret_key",  os.getenv("SECRET_KEY",  "change_me_use_openssl_rand_hex_32")),
        "SERVER_HOST": srv.get("host",    os.getenv("SERVER_HOST", "0.0.0.0")),
        "SERVER_PORT": int(srv.get("port", os.getenv("SERVER_PORT", "9003"))),
        "ACCESS_TOKEN_EXPIRE_MINUTES": int(srv.get("token_expire_minutes", "480")),
        "ADMIN_SECRET":        srv.get("admin_secret",        os.getenv("ADMIN_SECRET",        "")),
        "ADMIN_EMAIL":         srv.get("admin_email",         os.getenv("ADMIN_EMAIL",         "")),
        "ADMIN_PASSWORD_HASH": srv.get("admin_password_hash", os.getenv("ADMIN_PASSWORD_HASH", "")),
        "CLOUD_SYNC_URL":       srv.get("cloud_sync_url",       os.getenv("CLOUD_SYNC_URL",       "")),
        "CLOUD_SYNC_TOKEN":     srv.get("cloud_sync_token",     os.getenv("CLOUD_SYNC_TOKEN",     "")),
        "CLOUD_SYNC_ENABLED":   srv.get("cloud_sync_enabled",   os.getenv("CLOUD_SYNC_ENABLED",   "false")).lower() == "true",
        "cloud_tenant_id":      srv.get("cloud_tenant_id",      os.getenv("CLOUD_TENANT_ID",      "")),
        "cloud_owner_email":    srv.get("cloud_owner_email",    os.getenv("CLOUD_OWNER_EMAIL",    "")),
        "IDENTITY_PRIVATE_KEY": srv.get("identity_private_key", os.getenv("IDENTITY_PRIVATE_KEY", "")),
        "BILLING_URL":   srv.get("billing_url",   os.getenv("BILLING_URL",   "")),
        "CORS_ORIGINS":  srv.get("cors_origins",  os.getenv("CORS_ORIGINS",  "*")),
        "WEB_DIR":       srv.get("web_dir",       os.getenv("WEB_DIR",       "web")),
    }


class Settings(BaseSettings):
    SECRET_KEY: str = "change_me_use_openssl_rand_hex_32"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 480
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    DB_TYPE: str = "mysql"       # "mysql" | "sqlite"
    DB_HOST: str = "127.0.0.1"
    DB_PORT: int = 3307
    DB_NAME: str = "pos_db"
    DB_USER: str = "pos_user"
    DB_PASSWORD: str = ""
    DB_PATH: str = "./pos_data.db"

    SERVER_HOST: str = "0.0.0.0"
    SERVER_PORT: int = 9003

    # SaaS / multi-tenant
    STRIPE_WEBHOOK_SECRET: str = ""
    STRIPE_SECRET_KEY: str = ""
    STRIPE_PRICE_ID: str = ""
    STRIPE_SUCCESS_URL: str = ""
    STRIPE_CANCEL_URL: str = ""
    ADMIN_SECRET: str = ""
    ADMIN_EMAIL: str = ""
    ADMIN_PASSWORD_HASH: str = ""

    # Local ↔ Cloud synchronisation
    CLOUD_SYNC_URL:     str  = ""
    CLOUD_SYNC_TOKEN:   str  = ""
    CLOUD_SYNC_ENABLED: bool = False

    # Server identity — Ed25519 private key (base64 raw)
    # Generate: python -c "from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey; from cryptography.hazmat.primitives.serialization import Encoding,PrivateFormat,NoEncryption; import base64; k=Ed25519PrivateKey.generate(); print(base64.b64encode(k.private_bytes(Encoding.Raw,PrivateFormat.Raw,NoEncryption())).decode())"
    IDENTITY_PRIVATE_KEY: str = ""

    # URL du serveur billing (posconnect.ht). Séparé de CLOUD_SYNC_URL pour les
    # tenants self-hosted dont les données business vont vers leur propre serveur.
    BILLING_URL: str = ""

    # CORS — origines autorisées (séparées par virgule, ou "*" pour tout autoriser)
    # Production : "https://app.posconnect.ht,https://posconnect.ht"
    CORS_ORIGINS: str = "*"

    # Répertoire du build Flutter web (servi par FastAPI comme SPA)
    # Laisser vide pour désactiver le serving web intégré.
    WEB_DIR: str = "web"

    class Config:
        env_file = ".env"
        extra = "ignore"


def _make_settings() -> Settings:
    return Settings(**load_ini_config())


settings = _make_settings()


def get_database_url() -> str:
    import urllib.parse
    if settings.DB_TYPE == "sqlite":
        return f"sqlite:///{settings.DB_PATH}"
    pw = urllib.parse.quote_plus(settings.DB_PASSWORD)
    return (
        f"mysql+pymysql://{settings.DB_USER}:{pw}"
        f"@{settings.DB_HOST}:{settings.DB_PORT}/{settings.DB_NAME}"
    )


def write_ini_config(cfg_data: dict, path: Path = None) -> Path:
    """Write or update pos_server.ini with provided values."""
    target = path or _find_config_file()
    target.parent.mkdir(parents=True, exist_ok=True)

    cfg = configparser.ConfigParser()
    if target.exists():
        cfg.read(target, encoding="utf-8")

    if "database" not in cfg:
        cfg["database"] = {}
    if "server" not in cfg:
        cfg["server"] = {}

    for key, val in cfg_data.items():
        k = key.lower()
        if k in ("type", "host", "port", "name", "user", "password", "path"):
            cfg["database"][k] = str(val)
        elif k in ("secret_key", "token_expire_minutes", "admin_secret",
                   "admin_email", "admin_password_hash",
                   "cloud_sync_url", "cloud_sync_token", "cloud_sync_enabled",
                   "cloud_tenant_id", "cloud_owner_email",
                   "identity_private_key", "billing_url",
                   "cors_origins", "web_dir"):
            cfg["server"][k] = str(val)
        elif k == "server_host":
            cfg["server"]["host"] = str(val)
        elif k == "server_port":
            cfg["server"]["port"] = str(val)

    with open(target, "w", encoding="utf-8") as f:
        cfg.write(f)

    # Sur Windows : restreindre la lecture aux seuls SYSTEM et Administrators
    if os.name == "nt":
        try:
            import subprocess as _sp
            _sp.run(
                ["icacls", str(target), "/inheritance:r",
                 "/grant", "SYSTEM:(F)",
                 "/grant", "Administrators:(F)"],
                capture_output=True, timeout=5,
            )
        except Exception:
            pass

    return target
