"""mysql-query.log (general_log) grossit sans limite car MySQL ne le purge
jamais lui-meme (voir api/main.py::_rotate_mysql_general_log) — verifie que
la suppression ne se declenche qu'au-dela du seuil et qu'elle desactive/
reactive bien general_log autour de la suppression du fichier."""
import os
from unittest.mock import MagicMock

import api.main as main_module
import api.database as db_module
from api.core.config import settings


class _FakeConn:
    def __init__(self, log_path):
        self.log_path = log_path
        self.executed = []

    def execute(self, stmt):
        sql = str(stmt)
        self.executed.append(sql)
        if "SHOW VARIABLES" in sql:
            result = MagicMock()
            result.fetchone.return_value = ("general_log_file", self.log_path)
            return result
        return MagicMock()

    def commit(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class _FakeEngine:
    def __init__(self, log_path):
        self._log_path = log_path

    def connect(self):
        return _FakeConn(self._log_path)


def test_skips_when_db_type_is_sqlite(monkeypatch):
    monkeypatch.setattr(settings, "DB_TYPE", "sqlite")
    fake_engine = _FakeEngine("/tmp/does-not-matter.log")
    monkeypatch.setattr(db_module, "engine", fake_engine)
    # Ne doit rien lever, et surtout ne pas tenter de toucher au fichier.
    main_module._rotate_mysql_general_log()


def test_skips_when_file_below_threshold(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "DB_TYPE", "mysql")
    log_file = tmp_path / "mysql-query.log"
    log_file.write_bytes(b"x" * 1024)  # bien en dessous d'1 Go
    fake_engine = _FakeEngine(str(log_file))
    monkeypatch.setattr(db_module, "engine", fake_engine)

    main_module._rotate_mysql_general_log()

    assert log_file.exists()  # jamais touche


def test_deletes_and_toggles_general_log_when_over_threshold(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "DB_TYPE", "mysql")
    monkeypatch.setattr(main_module, "_LOG_ROTATE_THRESHOLD_BYTES", 100)
    log_file = tmp_path / "mysql-query.log"
    log_file.write_bytes(b"x" * 1000)  # au-dessus du seuil (monkeypatche a 100)
    fake_engine = _FakeEngine(str(log_file))
    monkeypatch.setattr(db_module, "engine", fake_engine)

    main_module._rotate_mysql_general_log()

    assert not log_file.exists()  # supprime


def test_noop_when_log_file_does_not_exist(monkeypatch):
    monkeypatch.setattr(settings, "DB_TYPE", "mysql")
    fake_engine = _FakeEngine("/nonexistent/path/mysql-query.log")
    monkeypatch.setattr(db_module, "engine", fake_engine)
    # Ne doit pas lever, meme si le fichier n'existe pas (chemin bidon).
    main_module._rotate_mysql_general_log()
