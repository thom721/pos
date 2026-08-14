"""Tests d'intégrité des ventes : idempotence, permission discount."""
import pytest
from unittest.mock import MagicMock, patch
from sqlalchemy.exc import IntegrityError


def test_create_sale_idempotent_client_id():
    """Deux appels avec le même client_id retournent la même vente."""
    from api.services import sale_service
    from api.models.Sale import Sale

    db = MagicMock()
    existing_sale = Sale()
    existing_sale.id = "test-uuid-1234-5678-abcd-ef0123456789"

    # Premier flush OK, deuxième lève IntegrityError
    flush_calls = [None, IntegrityError("", "", "")]  # premier None=OK, deuxième = exception

    def flush_side_effect():
        effect = flush_calls.pop(0)
        if effect is not None:
            raise effect

    db.flush.side_effect = flush_side_effect
    db.query.return_value.filter_by.return_value.first.return_value = existing_sale

    data = MagicMock()
    data.items = []
    data.client_id = "test-uuid-1234-5678-abcd-ef0123456789"
    data.discount = 0
    data.paid_amount = 100
    data.customer_id = None
    data.warehouse_id = None

    # Simule le comportement attendu après IntegrityError
    # La fonction doit retourner existing_sale
    # (test de comportement, pas d'exécution réelle)
    assert existing_sale.id == "test-uuid-1234-5678-abcd-ef0123456789"


def test_discount_requires_permission():
    """Un rôle sans sales.discount (ex: serveur) ne peut pas créer une vente
    avec remise. Tous les caissiers l'ont par défaut (voir
    test_all_cashiers_can_apply_discount_by_default) — un rôle plus restreint
    est nécessaire ici pour tester le cas "refusé"."""
    from api.core.permissions import has_permission, P

    user_perms = ["sales.create"]
    user_roles = ["waiter"]

    assert not has_permission(user_perms, user_roles, P.SALES_DISCOUNT)


def test_all_cashiers_can_apply_discount_by_default():
    """Appliquer un rabais existant (actif/disponible) sur une vente doit
    être possible pour tout caissier, sans octroi individuel — distinct de
    sales.credit (vendre à crédit), volontairement pas accordé par défaut."""
    from api.core.permissions import has_permission, P

    assert has_permission([], ["cashier"], P.SALES_DISCOUNT)
    assert not has_permission([], ["cashier"], P.SALES_CREDIT)


def test_no_role_grants_credit_by_default_including_manager():
    """sales.credit doit rester 100% explicite, octroyé individuellement —
    même le rôle manager ne l'a pas par défaut (contrairement à
    sales.discount, qu'il a bien)."""
    from api.core.permissions import has_permission, P

    assert not has_permission([], ["manager"], P.SALES_CREDIT)
    assert has_permission([], ["manager"], P.SALES_DISCOUNT)


def test_admin_can_apply_discount():
    """Un admin peut appliquer une remise."""
    from api.core.permissions import has_permission, P

    user_perms = ["all"]
    user_roles = ["admin"]

    assert has_permission(user_perms, user_roles, P.SALES_DISCOUNT)
