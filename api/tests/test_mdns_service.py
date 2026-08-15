"""mDNS diffuse "infini-post.local" sur le reseau local (Windows self-hosted
uniquement) — voir api/services/mdns_service.py. Ces tests verifient le
comportement best-effort (jamais d'exception qui remonte) et que
start/stop sont surs a appeler plusieurs fois."""
from api.services import mdns_service


def test_local_ip_returns_a_string_or_none():
    ip = mdns_service._local_ip()
    assert ip is None or isinstance(ip, str)


def test_start_and_stop_do_not_raise():
    mdns_service.start_mdns_responder(port=9443)
    mdns_service.stop_mdns_responder()


def test_stop_without_start_does_not_raise():
    mdns_service.stop_mdns_responder()
    mdns_service.stop_mdns_responder()


def test_double_start_does_not_raise():
    mdns_service.start_mdns_responder(port=9443)
    try:
        mdns_service.start_mdns_responder(port=9443)
    finally:
        mdns_service.stop_mdns_responder()


def test_refresh_without_start_is_a_noop():
    mdns_service.stop_mdns_responder()
    mdns_service.refresh_if_ip_changed()  # ne doit pas lever, ni redemarrer quoi que ce soit


def test_refresh_restarts_when_ip_changed(monkeypatch):
    mdns_service.start_mdns_responder(port=9443)
    try:
        original_ip = mdns_service._current_ip
        assert original_ip is not None

        calls = []
        real_start = mdns_service.start_mdns_responder

        def _spy_start(port=443):
            calls.append(port)
            real_start(port=port)

        monkeypatch.setattr(mdns_service, "_local_ip", lambda: "10.0.0.99")
        monkeypatch.setattr(mdns_service, "start_mdns_responder", _spy_start)

        mdns_service.refresh_if_ip_changed()

        assert calls == [9443]
        assert mdns_service._current_ip == "10.0.0.99"
    finally:
        mdns_service.stop_mdns_responder()


def test_refresh_does_nothing_when_ip_unchanged(monkeypatch):
    mdns_service.start_mdns_responder(port=9443)
    try:
        same_ip = mdns_service._current_ip
        monkeypatch.setattr(mdns_service, "_local_ip", lambda: same_ip)

        called = []
        monkeypatch.setattr(
            mdns_service, "start_mdns_responder",
            lambda port=443: called.append(port),
        )

        mdns_service.refresh_if_ip_changed()

        assert called == []
    finally:
        mdns_service.stop_mdns_responder()
