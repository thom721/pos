import asyncio
import logging

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from api.core.security import verify_token
from api.database import SessionLocal
from api.models.User import User
from api.ws_manager import manager

_log = logging.getLogger("pos.ws")
router = APIRouter(tags=["WebSocket"])

_PING_INTERVAL = 30  # seconds — keepalive sent to client when idle


@router.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    token: str = Query(...),
    warehouse_id: str | None = Query(None),
):
    """
    Persistent connection for Android and desktop clients (web still relies
    on periodic polling — see websocket_service.dart).
    The server pushes {"type": "sync"} whenever a write mutation completes
    for the connected tenant, so the client can refresh immediately instead
    of waiting for the fallback timer.
    Auth: JWT passed as ?token= query parameter (standard Bearer token).
    """
    payload = verify_token(token)
    if not payload:
        await websocket.close(code=4001)
        return

    # Cloud login JWT carries tenant_id directly in the payload
    tenant_id: str | None = payload.get("tenant_id")

    # Toujours résoudre l'utilisateur (par sub) pour permettre le push ciblé
    # par utilisateur (ex: forcer une reconnexion sur changement de permissions),
    # et en repli pour retrouver tenant_id sur un token local/legacy.
    sub = payload.get("sub")
    user_id: str | None = None
    db = SessionLocal()
    try:
        user = db.query(User).filter(
            (User.id == sub) | (User.username == sub)
        ).first()
        if user:
            user_id = user.id
            if not tenant_id:
                tenant_id = user.tenant_id
    finally:
        db.close()

    if not tenant_id:
        await websocket.close(code=4001)
        return

    # Dépôts suivis : ceux de l'utilisateur (liste) ; pour une installation
    # locale (token de synchro), le dépôt qu'elle envoie — vérifié contre le tenant.
    warehouses: set[str] | None = None
    if user_id is not None and user is not None:
        raw = getattr(user, "warehouse_id", None)
        if isinstance(raw, list) and raw:
            warehouses = {str(w) for w in raw}
    elif warehouse_id:
        from api.models.Warehouse import Warehouse
        db2 = SessionLocal()
        try:
            wh = db2.query(Warehouse).filter(
                Warehouse.id == warehouse_id, Warehouse.tenant_id == tenant_id
            ).first()
        finally:
            db2.close()
        if wh:
            warehouses = {wh.id}

    await manager.connect(websocket, tenant_id, user_id, warehouses)
    try:
        while True:
            try:
                # Wait for a client message (keepalive ping from client)
                await asyncio.wait_for(
                    websocket.receive_text(), timeout=float(_PING_INTERVAL)
                )
            except asyncio.TimeoutError:
                # No message from client — send server-side ping
                await websocket.send_json({"type": "ping"})
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        _log.debug("WS closed unexpectedly: %s", exc)
    finally:
        manager.disconnect(websocket, tenant_id, user_id)
