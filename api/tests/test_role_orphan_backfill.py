"""Backfill des rôles personnalisés orphelins (api/main.py
_backfill_custom_role_ownership / _owning_tenants_for_role) — avant le
correctif d'isolation des rôles, create_role ne renseignait jamais
tenant_id. Sans ce backfill, ces rôles deviendraient invisibles dans la
page Utilisateurs & Rôles de tout le monde une fois list_roles/update_role
scopés par tenant (voir test_role_tenant_isolation.py pour l'isolation
elle-même)."""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import pytest

import api.models  # noqa: F401
from api.database import Base
from api.main import (
    _owning_tenants_for_role,
    _repair_role_uniqueness,
    _backfill_custom_role_ownership,
)


def test_owning_tenants_for_role_single_tenant():
    users = [("tenant-a", ["cashier", "superviseur"]), ("tenant-a", ["manager"])]
    assert _owning_tenants_for_role("superviseur", users) == ["tenant-a"]


def test_owning_tenants_for_role_multiple_tenants_deduplicated_and_sorted():
    users = [
        ("tenant-b", ["superviseur"]),
        ("tenant-a", ["superviseur"]),
        ("tenant-a", ["superviseur"]),  # même tenant, deuxième utilisateur — pas de doublon
    ]
    assert _owning_tenants_for_role("superviseur", users) == ["tenant-a", "tenant-b"]


def test_owning_tenants_for_role_none_found():
    users = [("tenant-a", ["cashier"])]
    assert _owning_tenants_for_role("superviseur", users) == []


def test_owning_tenants_for_role_ignores_users_without_tenant():
    """Compte local (tenant_id NULL) — jamais compté comme un tenant propriétaire."""
    users = [(None, ["superviseur"]), ("tenant-a", ["superviseur"])]
    assert _owning_tenants_for_role("superviseur", users) == ["tenant-a"]


def test_owning_tenants_for_role_handles_null_roles_column():
    """User.roles peut être NULL en DB — ne doit pas planter."""
    users = [("tenant-a", None), ("tenant-b", ["superviseur"])]
    assert _owning_tenants_for_role("superviseur", users) == ["tenant-b"]


def test_repair_role_uniqueness_noop_on_sqlite():
    """SQLite (installs locales, suite de tests) : garde-fou MySQL uniquement
    — ne doit jamais lever d'exception ni tenter d'ALTER TABLE."""
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    _repair_role_uniqueness(engine)  # ne doit pas lever


def test_backfill_custom_role_ownership_noop_on_sqlite():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    _backfill_custom_role_ownership(engine)  # ne doit pas lever
