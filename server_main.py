#!/usr/bin/env python3
"""
POS Connect Server — point d'entrée pour la compilation Nuitka.

Utilisation normale  :  python server_main.py
Binaire compilé      :  ./posconnect-server  (ou .exe sur Windows)
"""
import os
import sys
import pathlib
import argparse

# ── Imports explicites pour Nuitka ────────────────────────────────────────────
# SQLAlchemy charge pymysql dynamiquement via l'URL "mysql+pymysql://",
# Pydantic charge email_validator dynamiquement, etc.
# Sans ces imports ici, Nuitka ne les inclut pas dans le binaire standalone.
import pymysql           # noqa: F401
import alembic           # noqa: F401
import email_validator   # noqa: F401
import pwdlib            # noqa: F401
import passlib           # noqa: F401
import argon2            # noqa: F401
import bcrypt            # noqa: F401
import jose              # noqa: F401
import jwt               # noqa: F401
import multipart         # noqa: F401
import dotenv            # noqa: F401


def _fix_workdir() -> None:
    """Bascule le CWD vers le dossier du binaire quand compilé avec Nuitka."""
    try:
        _ = __compiled__   # noqa: F821 — builtin Nuitka uniquement
        exe_dir = pathlib.Path(sys.executable).parent.resolve()
        os.chdir(exe_dir)
    except NameError:
        pass  # mode source normal


def main() -> None:
    _fix_workdir()

    parser = argparse.ArgumentParser(description="POS Connect – Serveur API")
    parser.add_argument("--host",   default="",  help="Adresse d'écoute (défaut: pos_server.ini)")
    parser.add_argument("--port",   type=int, default=0, help="Port d'écoute (défaut: pos_server.ini)")
    parser.add_argument("--reload", action="store_true", help="Rechargement auto (développement)")
    args = parser.parse_args()

    from api.core.config import settings
    from api.main import app

    host = args.host or settings.SERVER_HOST
    port = args.port or settings.SERVER_PORT

    import uvicorn
    uvicorn.run(
        "api.main:app" if args.reload else app,
        host=host,
        port=port,
        log_level="info",
        reload=args.reload,
    )


if __name__ == "__main__":
    main()
