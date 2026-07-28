import asyncio
import logging
from typing import Dict, Set

from fastapi import WebSocket

_log = logging.getLogger("pos.ws")


class ConnectionManager:
    def __init__(self) -> None:
        self._connections: Dict[str, Set[WebSocket]] = {}
        self._user_connections: Dict[str, Set[WebSocket]] = {}

    async def connect(self, ws: WebSocket, tenant_id: str, user_id: str | None = None) -> None:
        await ws.accept()
        self._connections.setdefault(tenant_id, set()).add(ws)
        if user_id:
            self._user_connections.setdefault(user_id, set()).add(ws)
        _log.info("WS connect tenant=%s user=%s sockets=%d", tenant_id, user_id, len(self._connections[tenant_id]))

    def disconnect(self, ws: WebSocket, tenant_id: str, user_id: str | None = None) -> None:
        conns = self._connections.get(tenant_id)
        if conns:
            conns.discard(ws)
            if not conns:
                del self._connections[tenant_id]
        if user_id:
            user_conns = self._user_connections.get(user_id)
            if user_conns:
                user_conns.discard(ws)
                if not user_conns:
                    del self._user_connections[user_id]

    async def notify(self, tenant_id: str) -> None:
        conns = list(self._connections.get(tenant_id, set()))
        if not conns:
            return
        dead: list[WebSocket] = []
        for ws in conns:
            try:
                await ws.send_json({"type": "sync"})
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws, tenant_id)

    async def notify_user(self, user_id: str, payload: dict) -> None:
        """Envoie un message ciblé à toutes les connexions d'un utilisateur précis
        (ex: forcer une reconnexion suite à un changement de permissions)."""
        conns = list(self._user_connections.get(user_id, set()))
        dead: list[WebSocket] = []
        for ws in conns:
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            conns_set = self._user_connections.get(user_id)
            if conns_set:
                conns_set.discard(ws)

    def connection_count(self, tenant_id: str) -> int:
        return len(self._connections.get(tenant_id, set()))

    def notify_threadsafe(self, tenant_id: str) -> None:
        """Fire-and-forget notify from a synchronous context (e.g. a threadpool endpoint)."""
        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                loop.call_soon_threadsafe(
                    lambda: asyncio.ensure_future(self.notify(tenant_id))
                )
        except RuntimeError:
            pass

    def notify_user_threadsafe(self, user_id: str, payload: dict) -> None:
        """Fire-and-forget notify_user from a synchronous context."""
        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                loop.call_soon_threadsafe(
                    lambda: asyncio.ensure_future(self.notify_user(user_id, payload))
                )
        except RuntimeError:
            pass


manager = ConnectionManager()
