"""Les signaux 'sync' ciblés par dépôt : un dépôt ne reçoit pas les signaux
des autres dépôts du même tenant."""
import asyncio

from api.ws_manager import ConnectionManager


class FakeWS:
    def __init__(self):
        self.sent = []

    async def accept(self):
        return None

    async def send_json(self, payload):
        self.sent.append(payload)


def _run(coro):
    return asyncio.new_event_loop().run_until_complete(coro)


def test_notify_with_warehouse_reaches_only_that_depot():
    m = ConnectionManager()
    a, b = FakeWS(), FakeWS()
    _run(m.connect(a, "T1", None, {"wh-A"}))
    _run(m.connect(b, "T1", None, {"wh-B"}))
    _run(m.notify("T1", "wh-A"))
    assert len(a.sent) == 1
    assert b.sent == []


def test_connection_without_depot_receives_everything():
    m = ConnectionManager()
    a, legacy = FakeWS(), FakeWS()
    _run(m.connect(a, "T1", None, {"wh-A"}))
    _run(m.connect(legacy, "T1", None, None))
    _run(m.notify("T1", "wh-B"))
    assert a.sent == []
    assert len(legacy.sent) == 1


def test_notify_without_depot_keeps_tenant_wide_behavior():
    m = ConnectionManager()
    a, b = FakeWS(), FakeWS()
    _run(m.connect(a, "T1", None, {"wh-A"}))
    _run(m.connect(b, "T1", None, {"wh-B"}))
    _run(m.notify("T1"))
    assert len(a.sent) == 1 and len(b.sent) == 1


def test_other_tenant_never_receives():
    m = ConnectionManager()
    a = FakeWS()
    _run(m.connect(a, "T1", None, {"wh-A"}))
    _run(m.notify("T2", "wh-A"))
    assert a.sent == []
