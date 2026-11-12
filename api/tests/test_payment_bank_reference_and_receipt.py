"""Un gros client qui règle une créance par virement bancaire doit pouvoir
laisser une référence de transaction (réconciliation bancaire) et un reçu
scanné/photographié — ni l'un ni l'autre n'existaient avant (voir
debts_screen.dart, le dialogue "Ajouter un paiement" n'envoyait que
method: 'CASH' en dur)."""
import asyncio
import io
import os
import shutil
from types import SimpleNamespace

import pytest
from fastapi import HTTPException, UploadFile
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import api.models  # noqa: F401
from api.database import Base
from api.models.Payment import Payment
from api.models.Sale import Sale, SaleStatus
from api.models.Tenant import Tenant
from api.models.Warehouse import Warehouse
from api.routes.payments import upload_payment_receipt
from api.services import payment_service

_RECEIPTS_DIR = "api/static/payment_receipts"


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


@pytest.fixture(autouse=True)
def _cleanup_receipts_dir():
    yield
    if os.path.isdir(_RECEIPTS_DIR):
        shutil.rmtree(_RECEIPTS_DIR)


@pytest.fixture()
def sale(db):
    t = Tenant(business_name="T", owner_email="t@t.com", slug="t")
    db.add(t)
    db.flush()
    wh = Warehouse(tenant_id=t.id, name="Dépôt", is_active=True, is_default=True)
    db.add(wh)
    db.flush()
    s = Sale(tenant_id=t.id, user_id=None, warehouse_id=wh.id,
              reference="V-1", total_amount=1000, final_amount=1000,
              paid_amount=0, status=SaleStatus.credit)
    db.add(s)
    db.commit()
    return s, t


def _user(tenant_id):
    return SimpleNamespace(id="u1", tenant_id=tenant_id, roles=["cashier"])


def test_add_payment_stores_bank_reference(db, sale):
    s, t = sale
    payment_service.add_payment(
        db,
        SimpleNamespace(reference_type="SALE", reference_id=s.id,
                         amount=600, method="bank", bank_reference="VIR-20261113-042"),
        user_id="u1", tenant_id=t.id,
    )
    db.commit()
    payment = db.query(Payment).filter_by(reference_id=s.id).first()
    assert payment.bank_reference == "VIR-20261113-042"


def test_add_payment_without_bank_reference_leaves_it_null(db, sale):
    s, t = sale
    payment_service.add_payment(
        db,
        SimpleNamespace(reference_type="SALE", reference_id=s.id, amount=600, method="cash"),
        user_id="u1", tenant_id=t.id,
    )
    db.commit()
    payment = db.query(Payment).filter_by(reference_id=s.id).first()
    assert payment.bank_reference is None


def test_upload_receipt_sets_url_and_rejects_cross_tenant(db, sale):
    s, t = sale
    payment = payment_service.add_payment(
        db,
        SimpleNamespace(reference_type="SALE", reference_id=s.id, amount=600, method="bank"),
        user_id="u1", tenant_id=t.id,
    )
    db.commit()

    png_bytes = b"\x89PNG\r\n\x1a\n" + b"0" * 20
    file = UploadFile(file=io.BytesIO(png_bytes), filename="recu.png")
    result = asyncio.run(upload_payment_receipt(
        payment.id, file=file, db=db, current_user=_user(t.id),
    ))
    assert result.receipt_url is not None
    assert result.receipt_url.startswith("/static/payment_receipts/")
    saved_path = os.path.join("api", result.receipt_url.lstrip("/"))
    assert os.path.exists(saved_path)

    # Un autre tenant ne doit jamais pouvoir lire/écraser ce reçu.
    other_tenant_id = "other-tenant"
    with pytest.raises(HTTPException) as exc:
        asyncio.run(upload_payment_receipt(
            payment.id,
            file=UploadFile(file=io.BytesIO(png_bytes), filename="recu2.png"),
            db=db, current_user=_user(other_tenant_id),
        ))
    assert exc.value.status_code == 404


def test_upload_receipt_rejects_bad_extension(db, sale):
    s, t = sale
    payment = payment_service.add_payment(
        db,
        SimpleNamespace(reference_type="SALE", reference_id=s.id, amount=600, method="bank"),
        user_id="u1", tenant_id=t.id,
    )
    db.commit()

    file = UploadFile(file=io.BytesIO(b"not an image"), filename="recu.exe")
    with pytest.raises(HTTPException) as exc:
        asyncio.run(upload_payment_receipt(
            payment.id, file=file, db=db, current_user=_user(t.id),
        ))
    assert exc.value.status_code == 400
