import asyncio
import logging
from typing import Dict, Set

from fastapi import WebSocket

_log = logging.getLogger("pos.ws")


class ConnectionManager:
    def __init__(self) -> None:
        self._connections: Dict[str, Set[WebSocket]] = {}

    async def connect(self, ws: WebSocket, tenant_id: str) -> None:
        await ws.accept()
        self._connections.setdefault(tenant_id, set()).add(ws)
        _log.info("WS connect tenant=%s sockets=%d", tenant_id, len(self._connections[tenant_id]))

    def disconnect(self, ws: WebSocket, tenant_id: str) -> None:
        conns = self._connections.get(tenant_id)
        if conns:
            conns.discard(ws)
            if not conns:
                del self._connections[tenant_id]

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

    def connection_count(self, tenant_id: str) -> int:
        return len(self._connections.get(tenant_id, set()))


manager = ConnectionManager()
