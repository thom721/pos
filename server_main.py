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
import passlib.handlers  # noqa: F401 - chargé dynamiquement par passlib.context
import passlib.handlers.bcrypt   # noqa: F401
import passlib.handlers.argon2   # noqa: F401
import passlib.handlers.sha2_crypt  # noqa: F401
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


def _crash_log_path() -> pathlib.Path:
    # Priorité : ProgramData (visible facilement) → dossier de l'exe (fallback)
    try:
        import os
        prog_data = os.environ.get("PROGRAMDATA") or r"C:\ProgramData"
        candidate = pathlib.Path(prog_data) / "POS_Connect" / "posconnect-crash.log"
        candidate.parent.mkdir(parents=True, exist_ok=True)
        return candidate
    except Exception:
        return pathlib.Path(sys.executable).parent / "posconnect-crash.log"


def _write_crash_log(tb_text: str) -> str:
    import datetime
    log_path = _crash_log_path()
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(f"\n{'=' * 60}\n")
        f.write(f"CRASH {datetime.datetime.now().isoformat()}\n")
        f.write(tb_text)
    return str(log_path)


def _show_crash_popup(log_path: str, summary: str) -> None:
    # MessageBoxW ne fonctionne pas depuis un service Windows (session 0 isolée).
    # On tente quand même : si l'exe est lancé manuellement ça marche, sinon ça échoue silencieusement.
    try:
        import ctypes
        ctypes.windll.user32.MessageBoxW(  # type: ignore[attr-defined]
            0,
            f"Le serveur n'a pas pu démarrer :\n\n{summary}\n\nDétails dans :\n{log_path}",
            "POS Connect — Erreur de démarrage",
            0x10,  # MB_ICONERROR
        )
    except Exception:
        pass


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
    try:
        main()
    except BaseException as _exc:
        # BaseException attrape aussi SystemExit (levé par uvicorn sur erreur de port, etc.)
        # On skip SystemExit(0) = arrêt propre.
        if isinstance(_exc, SystemExit) and _exc.code == 0:
            sys.exit(0)
        import traceback
        tb = traceback.format_exc()
        log_path = _write_crash_log(tb)
        summary = tb.strip().splitlines()[-1] if tb.strip() else "Erreur inconnue"
        _show_crash_popup(log_path, summary)
        sys.exit(getattr(_exc, "code", 1) or 1)
