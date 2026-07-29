import json
import secrets
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy.orm import Session

from api.models.ClientSabotage import ClientSabotage
from api.models.Depot import Depot
from api.models.Retrait import Retrait


def generate_account_number(db: Session, tenant_id: str | None) -> str:
    """Numéro de compte à 6 chiffres, unique par tenant. Boucle collision-retry
    (mirror du pattern username, api/routes/admin.py:458-460) — pas de compteur
    global (voir le bug corrigé de invoice_number, commit d65c127)."""
    while True:
        candidate = f"{secrets.randbelow(1_000_000):06d}"
        exists = (
            db.query(ClientSabotage)
            .filter(ClientSabotage.tenant_id == tenant_id, ClientSabotage.account_number == candidate)
            .first()
        )
        if not exists:
            return candidate


def create_client(
    db: Session,
    *,
    tenant_id: str | None,
    warehouse_id: str | None,
    nom: str,
    prenom: str,
    telephone: str,
    adresse: str,
    extra_fields: dict | None = None,
) -> ClientSabotage:
    exists = (
        db.query(ClientSabotage)
        .filter(ClientSabotage.tenant_id == tenant_id, ClientSabotage.telephone == telephone)
        .first()
    )
    if exists:
        raise HTTPException(400, f"Un client avec le téléphone « {telephone} » existe déjà")

    client = ClientSabotage(
        tenant_id=tenant_id,
        warehouse_id=warehouse_id,
        nom=nom,
        prenom=prenom,
        telephone=telephone,
        adresse=adresse,
        account_number=generate_account_number(db, tenant_id),
        extra_fields=json.dumps(extra_fields, ensure_ascii=False) if extra_fields else None,
    )
    db.add(client)
    db.commit()
    db.refresh(client)
    return client


def record_depot(
    db: Session,
    *,
    client_id: str,
    amount,
    tenant_id: str | None,
    warehouse_id: str | None,
    user_id: str | None = None,
    note: str | None = None,
) -> Depot:
    client = db.get(ClientSabotage, client_id)
    if not client:
        raise HTTPException(404, "Client introuvable")

    depot = Depot(
        client_id=client_id,
        tenant_id=tenant_id,
        warehouse_id=warehouse_id,
        user_id=user_id,
        amount=Decimal(str(amount)),
        note=note,
    )
    db.add(depot)
    db.commit()
    db.refresh(depot)
    return depot


def record_retrait(
    db: Session,
    *,
    client_id: str,
    amount,
    tenant_id: str | None,
    warehouse_id: str | None,
    user_id: str | None = None,
    note: str | None = None,
) -> Retrait:
    client = db.get(ClientSabotage, client_id)
    if not client:
        raise HTTPException(404, "Client introuvable")

    amount = Decimal(str(amount))
    if amount > client.balance:
        raise HTTPException(400, "Solde insuffisant")

    retrait = Retrait(
        client_id=client_id,
        tenant_id=tenant_id,
        warehouse_id=warehouse_id,
        user_id=user_id,
        amount=amount,
        note=note,
    )
    db.add(retrait)
    db.commit()
    db.refresh(retrait)
    return retrait
