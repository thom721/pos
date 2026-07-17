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
async def websocket_endpoint(websocket: WebSocket, token: str = Query(...)):
    """
    Persistent connection for Android offline-first clients.
    The server pushes {"type": "sync"} whenever a write mutation completes
    for the connected tenant, so the client can drain its offline queue and
    refresh its SQLite cache immediately instead of waiting for the timer.
    Auth: JWT passed as ?token= query parameter (standard Bearer token).
    """
    payload = verify_token(token)
    if not payload:
        await websocket.close(code=4001)
        return

    # Cloud login JWT carries tenant_id directly in the payload
    tenant_id: str | None = payload.get("tenant_id")

    if not tenant_id:
        # Fallback: local/legacy token — look up the user by sub
        sub = payload.get("sub")
        db = SessionLocal()
        try:
            user = db.query(User).filter(
                (User.id == sub) | (User.username == sub)
            ).first()
            tenant_id = user.tenant_id if user else None
        finally:
            db.close()

    if not tenant_id:
        await websocket.close(code=4001)
        return

    await manager.connect(websocket, tenant_id)
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
        manager.disconnect(websocket, tenant_id)
