"""Fallback SPA pour usePathUrlStrategy() (URLs Flutter web sans # — voir
frontend/lib/main.dart) : sur le serveur local self-hosted (pas de nginx
devant, contrairement au cloud qui a déjà try_files), FastAPI doit lui-même
servir index.html pour toute route profonde (ex: /dashboard) au lieu de 404,
tout en continuant à servir les vrais fichiers statiques normalement et sans
permettre de sortir de web/ (path traversal)."""
from fastapi.testclient import TestClient

import api.main as main_module

client = TestClient(main_module.app, raise_server_exceptions=True)


def test_deep_spa_route_serves_index_html():
    res = client.get("/dashboard")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]
    with open("web/index.html", "rb") as f:
        assert res.content == f.read()


def test_nested_deep_spa_route_serves_index_html():
    res = client.get("/business/warehouses/some-id")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]


def test_real_static_asset_still_served_directly():
    res = client.get("/main.dart.js")
    assert res.status_code == 200
    assert "javascript" in res.headers["content-type"]


def test_api_routes_unaffected_by_spa_fallback():
    res = client.get("/api/public/pricing")
    assert res.status_code == 200
    assert "text/html" not in res.headers["content-type"]


def test_path_traversal_blocked():
    res = client.get("/../../../../etc/passwd")
    # Starlette normalise déjà ".." dans le chemin avant que la route ne le
    # voie — quel que soit le comportement exact, jamais de contenu du
    # système de fichiers hors web/ ; au pire index.html (SPA fallback).
    assert res.status_code in (200, 404)
    if res.status_code == 200:
        with open("web/index.html", "rb") as f:
            assert res.content == f.read()
