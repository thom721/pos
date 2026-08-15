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
