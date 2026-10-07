import asyncio
import logging
from typing import Dict, Set

from fastapi import WebSocket

_log = logging.getLogger("pos.ws")


class ConnectionManager:
    def __init__(self) -> None:
        self._connections: Dict[str, Set[WebSocket]] = {}
        self._user_connections: Dict[str, Set[WebSocket]] = {}
        # Dépôts suivis par connexion. None = toutes les notifications du tenant
        # (ex: utilisateur sans dépôt, ou ancien client sans précision).
        self._scope: Dict[WebSocket, Set[str] | None] = {}

    async def connect(
        self,
        ws: WebSocket,
        tenant_id: str,
        user_id: str | None = None,
        warehouses: Set[str] | None = None,
    ) -> None:
        await ws.accept()
        self._scope[ws] = set(warehouses) if warehouses else None
        self._connections.setdefault(tenant_id, set()).add(ws)
        if user_id:
            self._user_connections.setdefault(user_id, set()).add(ws)
        _log.info("WS connect tenant=%s user=%s sockets=%d", tenant_id, user_id, len(self._connections[tenant_id]))

    def disconnect(self, ws: WebSocket, tenant_id: str, user_id: str | None = None) -> None:
        self._scope.pop(ws, None)
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

    async def notify(self, tenant_id: str, warehouse_id: str | None = None,
                     entities: list[str] | None = None) -> None:
        """Signal 'sync' au tenant. Avec warehouse_id : seulement aux connexions de
        ce dépôt, et à celles sans dépôt précis (données partagées)."""
        conns = list(self._connections.get(tenant_id, set()))
        if warehouse_id:
            conns = [
                ws for ws in conns
                if self._scope.get(ws) is None or warehouse_id in self._scope[ws]
            ]
        if not conns:
            _log.info("WS notify tenant=%s : aucune connexion active", tenant_id)
            return
        _log.info("WS notify tenant=%s : envoi sync à %d connexion(s)", tenant_id, len(conns))
        dead: list[WebSocket] = []
        payload = {"type": "sync"}
        if entities:
            payload["entities"] = entities
        for ws in conns:
            try:
                await ws.send_json(payload)
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

    async def notify_all(self, entities: list[str] | None = None) -> None:
        """Diffuse à TOUTES les connexions, tous tenants confondus — pour un
        changement qui n'est pas scopé à un tenant précis (ex: PlatformConfig,
        modifiée par le superadmin, affecte le prix/essai de tous les tenants
        d'un coup ; ou le pull de config publique côté serveur local, qui n'a
        qu'un seul tenant de toute façon)."""
        dead: list[tuple[str, WebSocket]] = []
        for tenant_id, conns in list(self._connections.items()):
            for ws in list(conns):
                try:
                    payload = {"type": "sync"}
                    if entities:
                        payload["entities"] = entities
                    await ws.send_json(payload)
                except Exception:
                    dead.append((tenant_id, ws))
        for tenant_id, ws in dead:
            self.disconnect(ws, tenant_id)

    def notify_threadsafe(self, tenant_id: str, warehouse_id: str | None = None,
                          entities: list[str] | None = None) -> None:
        """Fire-and-forget notify from a synchronous context (e.g. a threadpool endpoint)."""
        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                loop.call_soon_threadsafe(
                    lambda: asyncio.ensure_future(self.notify(tenant_id, warehouse_id, entities))
                )
        except RuntimeError:
            pass

    def notify_all_threadsafe(self, entities: list[str] | None = None) -> None:
        """Fire-and-forget notify_all from a synchronous context."""
        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                loop.call_soon_threadsafe(
                    lambda: asyncio.ensure_future(self.notify_all(entities))
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
