"""Le sync ne transfere que logo_path (une chaine), jamais les octets de
l'image (voir local_sync_service._row_to_dict, qui serialise les colonnes
telles quelles). _ensure_logo_file() comble ce trou : quand la sync pull
reçoit un app_config avec un logo_path dont le fichier n'existe pas
localement, elle le telecharge depuis le cloud."""
import os
import uuid

import api.services.local_sync_service as lss


class _FakeResponse:
    def __init__(self, status_code=200, content=b"fake-png-bytes"):
        self.status_code = status_code
        self.content = content


def _tmp_logo_path():
    return f"/static/logos/test-{uuid.uuid4()}.png"


def test_noop_when_logo_path_is_empty(monkeypatch):
    called = []
    monkeypatch.setattr(lss.httpx, "get", lambda *a, **k: called.append(1))
    lss._ensure_logo_file("https://cloud.example", "tok", None)
    lss._ensure_logo_file("https://cloud.example", "tok", "")
    assert called == []


def test_noop_when_file_already_exists_locally():
    logo_path = _tmp_logo_path()
    local_path = os.path.join("api", logo_path.lstrip("/"))
    os.makedirs(os.path.dirname(local_path), exist_ok=True)
    with open(local_path, "wb") as f:
        f.write(b"already-here")
    try:
        def _boom(*a, **k):
            raise AssertionError("ne doit pas appeler le reseau si le fichier existe deja")
        import httpx as _httpx
        orig = _httpx.get
        _httpx.get = _boom
        try:
            lss._ensure_logo_file("https://cloud.example", "tok", logo_path)
        finally:
            _httpx.get = orig
    finally:
        os.remove(local_path)


def test_downloads_and_saves_when_missing_locally(monkeypatch):
    logo_path = _tmp_logo_path()
    local_path = os.path.join("api", logo_path.lstrip("/"))
    assert not os.path.exists(local_path)

    captured = {}
    def fake_get(url, headers=None, timeout=None):
        captured["url"] = url
        return _FakeResponse(200, b"real-bytes")
    monkeypatch.setattr(lss.httpx, "get", fake_get)

    try:
        lss._ensure_logo_file("https://cloud.example", "tok", logo_path)
        assert captured["url"] == f"https://cloud.example{logo_path}"
        assert os.path.exists(local_path)
        with open(local_path, "rb") as f:
            assert f.read() == b"real-bytes"
    finally:
        if os.path.exists(local_path):
            os.remove(local_path)


def test_does_not_raise_when_download_fails(monkeypatch):
    logo_path = _tmp_logo_path()
    local_path = os.path.join("api", logo_path.lstrip("/"))

    def fake_get(*a, **k):
        raise ConnectionError("offline")
    monkeypatch.setattr(lss.httpx, "get", fake_get)

    lss._ensure_logo_file("https://cloud.example", "tok", logo_path)  # ne doit pas lever
    assert not os.path.exists(local_path)


def test_does_not_save_when_cloud_returns_non_200(monkeypatch):
    logo_path = _tmp_logo_path()
    local_path = os.path.join("api", logo_path.lstrip("/"))

    monkeypatch.setattr(lss.httpx, "get", lambda *a, **k: _FakeResponse(404, b""))
    lss._ensure_logo_file("https://cloud.example", "tok", logo_path)
    assert not os.path.exists(local_path)
