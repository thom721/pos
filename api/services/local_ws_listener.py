"""Serveur local → cloud : écoute le push {"type": "sync"} du cloud (même
mécanisme que l'application mobile) et déclenche une synchro immédiate.

Le message ne transporte AUCUNE donnée et n'est jamais appliqué : il ne fait
que réveiller la synchro, qui reste filtrée par dépôt (en-tête X-Warehouse-Id).
"""
import asyncio
import json
import logging
from urllib.parse import urlencode, urlparse

import websockets

_log = logging.getLogger("pos.ws_listener")
_RECONNECT_MAX = 60  # secondes


def ws_url(sync_url: str, token: str, warehouse_id: str | None = None) -> str:
    """https://host/api → wss://host/api/ws?token=…[&warehouse_id=…] (endpoint /ws à la racine).
    Le dépôt permet au cloud de ne signaler que les changements de ce dépôt."""
    p = urlparse(sync_url)
    scheme = "wss" if p.scheme == "https" else "ws"
    params = {"token": token}
    if warehouse_id:
        params["warehouse_id"] = warehouse_id
    return f"{scheme}://{p.netloc}/ws?{urlencode(params)}"


def handle_message(raw, on_sync) -> bool:
    """Déclenche on_sync pour un message 'sync'. Renvoie True si déclenché."""
    try:
        msg = json.loads(raw)
    except (TypeError, ValueError):
        return False
    if isinstance(msg, dict) and msg.get("type") == "sync":
        on_sync()
        return True
    return False


async def run_listener(load_credentials, on_sync, load_warehouse=None) -> None:
    """Boucle de connexion avec reconnexion (backoff 1 → 60 s)."""
    delay = 1
    while True:
        url, token, enabled = await asyncio.to_thread(load_credentials)
        if not (enabled and url and token):
            await asyncio.sleep(60)
            continue
        warehouse_id = load_warehouse() if load_warehouse else None
        try:
            async with websockets.connect(ws_url(url, token, warehouse_id), open_timeout=15, ping_interval=None) as ws:
                delay = 1
                _log.info("WS cloud connecté — synchro immédiate sur push")
                async for raw in ws:
                    if handle_message(raw, on_sync):
                        _log.info("WS cloud : signal sync reçu — synchro déclenchée")
        except Exception as exc:
            _log.warning("WS cloud indisponible (%s) — nouvelle tentative dans %ss", exc, delay)
        await asyncio.sleep(delay)
        delay = min(delay * 2, _RECONNECT_MAX)
