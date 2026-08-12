"""notify_all() doit atteindre TOUTES les connexions, tous tenants confondus
— utilisé pour les changements non scopés à un tenant (PlatformConfig, admin
plateforme), contrairement à notify(tenant_id) qui ne cible qu'un tenant."""
import asyncio

from api.ws_manager import ConnectionManager


class _FakeWebSocket:
    def __init__(self, fail: bool = False):
        self.fail = fail
        self.sent: list[dict] = []

    async def accept(self):
        pass

    async def send_json(self, payload: dict):
        if self.fail:
            raise RuntimeError("socket closed")
        self.sent.append(payload)


def test_notify_all_reaches_every_tenant():
    async def _run():
        manager = ConnectionManager()
        ws_a = _FakeWebSocket()
        ws_b = _FakeWebSocket()
        await manager.connect(ws_a, "tenant-a")
        await manager.connect(ws_b, "tenant-b")

        await manager.notify_all()

        assert ws_a.sent == [{"type": "sync"}]
        assert ws_b.sent == [{"type": "sync"}]

    asyncio.run(_run())


def test_notify_all_drops_dead_connections():
    async def _run():
        manager = ConnectionManager()
        dead = _FakeWebSocket(fail=True)
        alive = _FakeWebSocket()
        await manager.connect(dead, "tenant-a")
        await manager.connect(alive, "tenant-b")

        await manager.notify_all()

        assert manager.connection_count("tenant-a") == 0
        assert manager.connection_count("tenant-b") == 1
        assert alive.sent == [{"type": "sync"}]

    asyncio.run(_run())
