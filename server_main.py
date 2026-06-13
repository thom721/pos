#!/usr/bin/env python3
"""
POS Connect Server — point d'entrée pour la compilation Nuitka.

Utilisation normale  :  python server_main.py
Binaire compilé      :  ./posconnect-server  (ou .exe sur Windows)
Options              :  --host 0.0.0.0 --port 8002
"""
import os
import sys
import pathlib
import argparse


def _fix_workdir() -> None:
    """
    Quand compilé avec Nuitka --standalone, sys.executable pointe vers le
    binaire dans le dossier dist.  On bascule le CWD là pour que
    pos_server.ini, alembic.ini et api/static soient trouvés correctement.
    """
    try:
        # __compiled__ est défini par Nuitka dans tous les modules compilés
        _ = __compiled__   # noqa: F821
        exe_dir = pathlib.Path(sys.executable).parent.resolve()
        os.chdir(exe_dir)
    except NameError:
        pass   # mode source normal — ne pas changer le CWD


def main() -> None:
    _fix_workdir()

    parser = argparse.ArgumentParser(description="POS Connect – Serveur API")
    parser.add_argument("--host",    default="",   help="Adresse d'écoute (défaut: pos_server.ini)")
    parser.add_argument("--port",    type=int, default=0, help="Port d'écoute (défaut: pos_server.ini)")
    parser.add_argument("--reload",  action="store_true", help="Rechargement auto (développement seulement)")
    args = parser.parse_args()

    # Charger la config APRÈS avoir fixé le CWD
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
