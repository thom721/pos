"""Bug reel : "role" avait bien ete ajoute a SYNC_ENTITIES (local) et
_MODEL_MAP (cloud), mais jamais a _SHARED_TENANT_ENTITIES. Role n'a pas de
colonne warehouse_id (un role n'est jamais propre a un depot) - sans cette
entree, _scope_to_warehouse() (api/routes/sync.py) tombait sur son dernier
cas par defaut, fail-closed : query.filter(sa_false()), renvoyant ZERO
ligne pour TOUTE requete de pull sur "role", quel que soit le curseur ou le
depot configure. Resultat vu en reel : aucun role personnalise n'a jamais
atteint un serveur local, meme apres reset du curseur de sync - seuls les
roles integres (seedes localement au demarrage, pas via la synchro)
etaient presents. Les tests precedents (test_sync_role_entity.py) ne
l'attrapaient pas car ils simulaient directement la reponse HTTP du pull,
sans jamais appeler _scope_to_warehouse (la vraie logique de filtrage cote
route cloud) - celui-ci l'exerce directement, comme le ferait une vraie
requete."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Tenant import Tenant
from api.models.Role import Role
from api.routes.sync import _scope_to_warehouse


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture()
def tenant(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    return t


def test_role_pull_query_not_scoped_to_warehouse(db, tenant):
    """Un role tenant-scope doit rester visible meme avec un wh_id
    renseigne (installation rattachee a un depot precis) — role n'est
    jamais propre a un depot, il doit toujours passer en entier."""
    role = Role(
        tenant_id=tenant.id, name="credit_caissier", label="Caissier + Credit",
        is_builtin=False, permissions=["sales.credit"],
    )
    db.add(role)
    db.commit()

    base_query = db.query(Role).filter(Role.tenant_id == tenant.id)

    # Avec un depot configure (cas reel : une installation locale rattachee
    # a "Depot principal" par exemple).
    scoped = _scope_to_warehouse(base_query, Role, "role", wh_id="un-depot-quelconque")
    assert scoped.count() == 1, (
        "le role personnalise est filtre a tort par le scope de depot — "
        "'role' doit figurer dans _SHARED_TENANT_ENTITIES"
    )

    # Sans depot configure du tout (cas fail-closed le plus strict).
    scoped_no_wh = _scope_to_warehouse(base_query, Role, "role", wh_id=None)
    assert scoped_no_wh.count() == 1, (
        "le role personnalise est filtre a tort meme sans wh_id — "
        "'role' doit figurer dans _SHARED_TENANT_ENTITIES"
    )
