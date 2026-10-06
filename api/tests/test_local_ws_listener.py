"""Le serveur local écoute le push 'sync' du cloud et ne fait que déclencher
une synchro. Aucun contenu de message n'est appliqué."""
import json

from api.services.local_ws_listener import handle_message, ws_url


def test_ws_url_https_to_wss_with_token():
    assert ws_url("https://pos.infini-software.cloud/api", "abc") == \
        "wss://pos.infini-software.cloud/ws?token=abc"


def test_ws_url_http_to_ws():
    assert ws_url("http://192.168.1.10:9003", "t") == "ws://192.168.1.10:9003/ws?token=t"


def test_sync_message_triggers_callback():
    calls = []
    assert handle_message(json.dumps({"type": "sync"}), lambda: calls.append(1)) is True
    assert calls == [1]


def test_other_messages_do_not_trigger():
    calls = []
    for raw in (json.dumps({"type": "ping"}), json.dumps({"type": "permissions_changed"}), "garbage", None):
        assert handle_message(raw, lambda: calls.append(1)) is False
    assert calls == []


def test_sync_message_payload_is_ignored():
    calls = []
    handle_message(json.dumps({"type": "sync", "records": [{"id": "x", "warehouse_id": "other"}]}),
                   lambda: calls.append(1))
    assert calls == [1]
