"""Entrepôt central : reçoit du stock (manuellement ou via réception d'achat),
distribue vers les dépôts du tenant selon une quantité choisie par dépôt, et
n'est jamais compté comme un dépôt de vente facturable. Un tenant peut créer
plusieurs entrepôts ; chacun a son propre abonnement (pas d'essai gratuit) et
la distribution est bloquée tant qu'il n'est pas payé."""
from datetime import timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException

import api.models  # noqa: F401
from api.database import Base
from api.core.dt_coerce import now_local
from api.models.Tenant import Tenant
from api.models.Category import Category
from api.models.Product import Product
from api.models.Warehouse import Warehouse
from api.models.BillingPayment import BillingPayment
from api.models.PlatformConfig import PlatformConfig
from api.models.Purchase import Purchase, PurchaseStatus
from api.models.PurchaseItem import PurchaseItem
from api.services import entrepot_service


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


@pytest.fixture()
def category(db, tenant):
    cat = Category(name="Cat", tenant_id=tenant.id)
    db.add(cat)
    db.flush()
    return cat


@pytest.fixture()
def depots(db, tenant):
    a = Warehouse(tenant_id=tenant.id, name="Dépôt A", is_active=True, is_default=True)
    b = Warehouse(tenant_id=tenant.id, name="Dépôt B", is_active=True, is_default=False)
    db.add_all([a, b])
    db.flush()
    return a, b


@pytest.fixture()
def product(db, tenant, category):
    p = Product(name="Produit", category_id=category.id, sale_price=100, purchase_price=50, tenant_id=tenant.id)
    db.add(p)
    db.flush()
    return p


def _mark_paid(db, entrepot, days=30):
    """Simule une confirmation de paiement admin (voir test dédié plus bas
    pour le vrai chemin admin.confirm_payment)."""
    entrepot.subscription_ends_at = now_local() + timedelta(days=days)
    db.flush()


def test_create_multiple_entrepots_for_same_tenant(db, tenant):
    """Un tenant peut créer plusieurs entrepôts — plus d'idempotence, chacun
    est une ligne distincte avec sa propre facturation."""
    e1 = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt Nord", "1 rue A")
    e2 = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt Sud", "2 rue B")
    assert e1.id != e2.id
    assert e1.address == "1 rue A"
    assert e2.address == "2 rue B"
    assert e1.is_entrepot is True and e2.is_entrepot is True

    all_entrepots = entrepot_service.list_entrepots(db, tenant.id)
    assert {e.id for e in all_entrepots} == {e1.id, e2.id}


def test_first_entrepot_gets_free_trial(db, tenant):
    """Le 1er entrepôt du tenant obtient automatiquement l'essai gratuit
    (PlatformConfig.entrepot_trial_days, 30 jours par défaut)."""
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    assert entrepot.subscription_ends_at is not None
    assert entrepot.subscription_ends_at > now_local() + timedelta(days=29)


def test_second_entrepot_has_no_free_trial_by_default(db, tenant):
    """Le 2e entrepôt (et les suivants) n'a PAS d'essai par défaut —
    entrepot_trial_all doit être activé explicitement pour l'étendre."""
    entrepot_service.create_entrepot(db, tenant.id, "Entrepôt A")
    second = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt B")
    assert second.subscription_ends_at is None


def test_entrepot_trial_all_extends_trial_to_every_entrepot(db, tenant):
    """entrepot_trial_all=True : même le 2e (et les suivants) obtient l'essai
    à la création, pas seulement le 1er."""
    db.add(PlatformConfig(entrepot_trial_all=True))
    db.flush()

    entrepot_service.create_entrepot(db, tenant.id, "Entrepôt A")
    second = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt B")
    assert second.subscription_ends_at is not None
    assert second.subscription_ends_at > now_local() + timedelta(days=29)


def test_entrepot_trial_days_configurable(db, tenant):
    db.add(PlatformConfig(entrepot_trial_days=7))
    db.flush()

    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    delta = entrepot.subscription_ends_at - now_local()
    assert timedelta(days=6) < delta <= timedelta(days=7)


def test_grant_missing_trials_only_updates_unpaid_entrepots(db, tenant):
    entrepot_a = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt A")  # essai auto (1er)
    entrepot_b = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt B")  # pas d'essai (2e)
    _mark_paid(db, entrepot_a, days=5)  # déjà payé — ne doit pas être touché
    original_end = entrepot_a.subscription_ends_at

    updated = entrepot_service.grant_missing_trials(db, tenant.id)

    assert updated == 1
    db.refresh(entrepot_a)
    db.refresh(entrepot_b)
    assert entrepot_a.subscription_ends_at == original_end  # inchangé
    assert entrepot_b.subscription_ends_at is not None
    assert entrepot_b.subscription_ends_at > now_local() + timedelta(days=29)


def test_create_entrepot_is_claimed_to_prevent_installation(db, tenant):
    """L'entrepôt n'est pas un poste de vente installable — is_claimed=True
    dès la création empêche GET/POST install-code et redeem-code de lui
    générer/valider un code (voir api/routes/warehouse.py, api/routes/sync.py)."""
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    assert entrepot.is_claimed is True


def test_entrepot_excluded_from_billing_depot_count(db, tenant, depots):
    from api.routes.billing import _compute_plan_usage

    entrepot_service.create_entrepot(db, tenant.id)
    usage = _compute_plan_usage(tenant, db, None)
    # depots = 2 (Dépôt A, Dépôt B) — l'entrepôt n'est pas compté
    assert usage["current_depots"] == 2
    assert len(usage["entrepots"]) == 1


def test_manual_adjustment_increases_entrepot_stock(db, tenant, product):
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(
        db, tenant.id, entrepot.id, product.id, 20, "Réception manuelle", "u1",
    )
    db.refresh(product)
    assert product.stock_at(entrepot.id) == 20


def test_purchase_receipt_targeting_entrepot_increases_its_stock(db, tenant, product):
    """Réception automatique : aucun code neuf — ReceiptService résout
    n'importe quel warehouse_id actif du tenant, l'entrepôt y compris."""
    from api.schemas.purchase_receipt import PurchaseReceiptCreate, ReceiptItemCreate
    from api.services.ReceiptService import ReceiptService

    entrepot = entrepot_service.create_entrepot(db, tenant.id)

    purchase = Purchase(
        tenant_id=tenant.id, reference="PO-1", total_amount=500,
        warehouse_id=entrepot.id, status=PurchaseStatus.pending,
    )
    db.add(purchase)
    db.flush()
    item = PurchaseItem(
        tenant_id=tenant.id, purchase_id=purchase.id, product_id=product.id,
        ordered_qty=10, unit_price=50, subtotal=500,
    )
    db.add(item)
    db.commit()

    payload = PurchaseReceiptCreate(
        purchase_id=purchase.id,
        warehouse_id=entrepot.id,
        items=[ReceiptItemCreate(
            purchase_item_id=item.id,
            purchase_receipt_id="unused",
            product_id=product.id,
            received_qty=10,
        )],
    )
    ReceiptService(db).receive(payload, user_id="u1", tenant_id=tenant.id)

    db.refresh(product)
    assert product.stock_at(entrepot.id) == 10


def test_distribute_rejected_when_entrepot_unpaid(db, tenant, product, depots):
    """Distribuer est bloqué (402) tant que l'entrepôt n'a pas d'abonnement/
    essai actif — recevoir du stock reste libre. Le 1er entrepôt obtient
    l'essai automatiquement (voir test_first_entrepot_gets_free_trial) ; on
    l'annule ici pour isoler le comportement "non payé" testé."""
    depot_a, _ = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot.subscription_ends_at = None
    db.flush()
    entrepot_service.adjust_entrepot_stock(db, tenant.id, entrepot.id, product.id, 30, None, "u1")

    with pytest.raises(HTTPException) as exc:
        entrepot_service.distribute(
            db, tenant.id, entrepot.id, product.id,
            [{"warehouse_id": depot_a.id, "quantity": 12}],
            "u1",
        )
    assert exc.value.status_code == 402

    db.refresh(product)
    assert product.stock_at(entrepot.id) == 30  # rien n'a bougé


def test_distribute_rejected_when_entrepot_subscription_expired(db, tenant, product, depots):
    depot_a, _ = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(db, tenant.id, entrepot.id, product.id, 30, None, "u1")
    _mark_paid(db, entrepot, days=-1)  # abonnement déjà expiré

    with pytest.raises(HTTPException) as exc:
        entrepot_service.distribute(
            db, tenant.id, entrepot.id, product.id,
            [{"warehouse_id": depot_a.id, "quantity": 12}],
            "u1",
        )
    assert exc.value.status_code == 402


def test_distribute_moves_stock_from_entrepot_to_target_depots(db, tenant, product, depots):
    depot_a, depot_b = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(db, tenant.id, entrepot.id, product.id, 30, None, "u1")
    _mark_paid(db, entrepot)

    entrepot_service.distribute(
        db, tenant.id, entrepot.id, product.id,
        [
            {"warehouse_id": depot_a.id, "quantity": 12},
            {"warehouse_id": depot_b.id, "quantity": 8},
        ],
        "u1",
    )

    db.refresh(product)
    assert product.stock_at(entrepot.id) == 10  # 30 - 12 - 8
    assert product.stock_at(depot_a.id) == 12
    assert product.stock_at(depot_b.id) == 8


def test_distribute_rejects_insufficient_entrepot_stock(db, tenant, product, depots):
    depot_a, _ = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(db, tenant.id, entrepot.id, product.id, 5, None, "u1")
    _mark_paid(db, entrepot)

    with pytest.raises(HTTPException) as exc:
        entrepot_service.distribute(
            db, tenant.id, entrepot.id, product.id,
            [{"warehouse_id": depot_a.id, "quantity": 10}],
            "u1",
        )
    assert exc.value.status_code == 400

    db.refresh(product)
    assert product.stock_at(entrepot.id) == 5  # inchangé — rien n'a été déplacé
    assert product.stock_at(depot_a.id) == 0


def test_distribute_rejects_invalid_target_warehouse(db, tenant, product):
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(db, tenant.id, entrepot.id, product.id, 30, None, "u1")
    _mark_paid(db, entrepot)

    with pytest.raises(HTTPException) as exc:
        entrepot_service.distribute(
            db, tenant.id, entrepot.id, product.id,
            [{"warehouse_id": "not-a-real-warehouse", "quantity": 5}],
            "u1",
        )
    assert exc.value.status_code == 404


def test_distribute_rejects_targeting_entrepot_itself(db, tenant, product):
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    entrepot_service.adjust_entrepot_stock(db, tenant.id, entrepot.id, product.id, 30, None, "u1")
    _mark_paid(db, entrepot)

    with pytest.raises(HTTPException) as exc:
        entrepot_service.distribute(
            db, tenant.id, entrepot.id, product.id,
            [{"warehouse_id": entrepot.id, "quantity": 5}],
            "u1",
        )
    assert exc.value.status_code == 400


def test_confirm_payment_extends_entrepot_subscription(db, tenant, depots):
    """Mirroring register_ids_json : confirmer un paiement entrepot_ids_json
    étend Warehouse.subscription_ends_at et débloque la distribution."""
    import json as _json
    from api.routes.admin import confirm_payment, ConfirmPaymentPayload

    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    payment = BillingPayment(
        tenant_id=tenant.id,
        invoice_number="ENT-2026-0001",
        method="cash",
        amount=500,
        currency="HTG",
        months=1,
        status="pending",
        plan_type="monthly",
        entrepot_ids_json=_json.dumps([entrepot.id]),
    )
    db.add(payment)
    db.commit()

    result = confirm_payment(payment.id, ConfirmPaymentPayload(), db, {})

    assert result["status"] == "ok"
    assert result["entrepots"][0]["entrepot_id"] == entrepot.id
    db.refresh(entrepot)
    assert entrepot.subscription_ends_at is not None
    assert entrepot.subscription_ends_at > now_local()

    # La distribution est maintenant débloquée.
    entrepot_service._assert_paid(entrepot)  # ne lève pas


def test_transfer_from_depot_to_entrepot_never_requires_payment(db, tenant, product, depots):
    """« Retourner à l'entrepôt » depuis un dépôt classique — recevoir dans
    l'entrepôt n'est jamais bloqué par l'abonnement (contrairement à
    distribute(), qui fait sortir du stock DE l'entrepôt)."""
    depot_a, _ = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id, address="1 rue A")
    from api.services.stock_service import record_stock_movement
    from api.models.StockMovement import StockType
    record_stock_movement(
        db, product_id=product.id, user_id="u1", tenant_id=tenant.id,
        warehouse_id=depot_a.id, type=StockType.in_, quantity=20,
        source_type="test_seed",
    )
    db.commit()

    receipt = entrepot_service.transfer_to_entrepot(
        db, tenant.id, entrepot.id, depot_a.id, product.id, 12, "u1", reason="Retour surplus",
    )

    assert receipt["quantity"] == 12
    assert receipt["source_name"] == "Dépôt A"
    assert receipt["target_name"] == entrepot.name
    assert receipt["target_address"] == "1 rue A"
    db.refresh(product)
    assert product.stock_at(depot_a.id) == 8   # 20 - 12
    assert product.stock_at(entrepot.id) == 12


def test_transfer_between_entrepots_requires_source_paid(db, tenant, product):
    """Transfert entrepôt → entrepôt : bloqué (402) si la source (celle qui
    perd du stock) n'a pas d'abonnement actif, comme pour distribute(). Le
    1er entrepôt (ent_a) obtient l'essai automatiquement — annulé ici pour
    isoler le comportement "non payé" testé."""
    ent_a = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt A")
    ent_a.subscription_ends_at = None
    db.flush()
    ent_b = entrepot_service.create_entrepot(db, tenant.id, "Entrepôt B")
    entrepot_service.adjust_entrepot_stock(db, tenant.id, ent_a.id, product.id, 30, None, "u1")

    with pytest.raises(HTTPException) as exc:
        entrepot_service.transfer_to_entrepot(
            db, tenant.id, ent_b.id, ent_a.id, product.id, 10, "u1",
        )
    assert exc.value.status_code == 402

    _mark_paid(db, ent_a)
    entrepot_service.transfer_to_entrepot(
        db, tenant.id, ent_b.id, ent_a.id, product.id, 10, "u1",
    )
    db.refresh(product)
    assert product.stock_at(ent_a.id) == 20
    assert product.stock_at(ent_b.id) == 10


def test_transfer_rejects_same_source_and_target(db, tenant, product):
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    with pytest.raises(HTTPException) as exc:
        entrepot_service.transfer_to_entrepot(
            db, tenant.id, entrepot.id, entrepot.id, product.id, 5, "u1",
        )
    assert exc.value.status_code == 400


def test_transfer_rejects_insufficient_source_stock(db, tenant, product, depots):
    depot_a, _ = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id)

    with pytest.raises(HTTPException) as exc:
        entrepot_service.transfer_to_entrepot(
            db, tenant.id, entrepot.id, depot_a.id, product.id, 5, "u1",
        )
    assert exc.value.status_code == 400


# ── Rattachement à un dépôt (linked_warehouse_id) ────────────────────────────

def test_create_entrepot_with_linked_warehouse(db, tenant, depots):
    depot_a, _ = depots
    entrepot = entrepot_service.create_entrepot(
        db, tenant.id, "Entrepôt X", linked_warehouse_id=depot_a.id,
    )
    assert entrepot.linked_warehouse_id == depot_a.id


def test_create_entrepot_rejects_unknown_linked_warehouse(db, tenant):
    with pytest.raises(HTTPException) as exc:
        entrepot_service.create_entrepot(db, tenant.id, linked_warehouse_id="does-not-exist")
    assert exc.value.status_code == 404


def test_create_entrepot_rejects_linking_to_another_entrepot(db, tenant):
    other_entrepot = entrepot_service.create_entrepot(db, tenant.id, "Autre entrepôt")
    with pytest.raises(HTTPException) as exc:
        entrepot_service.create_entrepot(
            db, tenant.id, "Entrepôt X", linked_warehouse_id=other_entrepot.id,
        )
    assert exc.value.status_code == 404


def test_update_entrepot_can_link_and_unlink(db, tenant, depots):
    depot_a, _ = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id)
    assert entrepot.linked_warehouse_id is None

    entrepot_service.update_entrepot(db, tenant.id, entrepot.id, linked_warehouse_id=depot_a.id)
    db.refresh(entrepot)
    assert entrepot.linked_warehouse_id == depot_a.id

    entrepot_service.update_entrepot(db, tenant.id, entrepot.id, linked_warehouse_id=None)
    db.refresh(entrepot)
    assert entrepot.linked_warehouse_id is None


def test_update_entrepot_without_linked_warehouse_kwarg_leaves_it_untouched(db, tenant, depots):
    depot_a, _ = depots
    entrepot = entrepot_service.create_entrepot(db, tenant.id, linked_warehouse_id=depot_a.id)

    entrepot_service.update_entrepot(db, tenant.id, entrepot.id, name="Nouveau nom")
    db.refresh(entrepot)
    assert entrepot.name == "Nouveau nom"
    assert entrepot.linked_warehouse_id == depot_a.id


# ── Création réservée au cloud (bloquée sur un poste local synchronisé) ─────

def test_create_entrepot_blocked_when_cloud_sync_enabled(db, tenant, monkeypatch):
    import api.services.entrepot_service as es
    monkeypatch.setattr(es.settings, "CLOUD_SYNC_ENABLED", True)
    with pytest.raises(HTTPException) as exc:
        entrepot_service.create_entrepot(db, tenant.id)
    assert exc.value.status_code == 403
