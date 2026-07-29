import json

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from sqlalchemy.orm import Session

from api.database import get_db
from api.dependencies.auth import require_permission
from api.core.permissions import P
from api.models.User import User
from api.models.ClientSabotage import ClientSabotage
from api.schemas.client_sabotage import ClientSabotageCreate, ClientSabotageRead, ClientSabotageUpdate
from api.services import sabotage_service
from api.services.warehouse_helper import resolve_warehouse_id
from api.ws_manager import manager

router = APIRouter(prefix="/api/clients-sabotage", tags=["ClientSabotage"])


@router.post("/", response_model=ClientSabotageRead)
def create_client(
    data: ClientSabotageCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CLIENTS_SABOTAGE_CREATE)),
):
    warehouse_id = resolve_warehouse_id(db, current_user.tenant_id, data.warehouse_id) \
        or resolve_warehouse_id(db, current_user.tenant_id)
    client = sabotage_service.create_client(
        db,
        tenant_id=current_user.tenant_id,
        warehouse_id=warehouse_id,
        nom=data.nom,
        prenom=data.prenom,
        telephone=data.telephone,
        adresse=data.adresse,
        extra_fields=data.extra_fields,
    )
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return client


@router.get("/")
def list_clients(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CLIENTS_SABOTAGE_READ)),
):
    q = db.query(ClientSabotage).filter(ClientSabotage.tenant_id == current_user.tenant_id)
    return {"data": [ClientSabotageRead.model_validate(c) for c in q.order_by(ClientSabotage.nom).all()]}


@router.get("/{client_id}", response_model=ClientSabotageRead)
def get_client(
    client_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CLIENTS_SABOTAGE_READ)),
):
    client = (
        db.query(ClientSabotage)
        .filter(ClientSabotage.id == client_id, ClientSabotage.tenant_id == current_user.tenant_id)
        .first()
    )
    if not client:
        raise HTTPException(404, "Client introuvable")
    return client


@router.put("/{client_id}", response_model=ClientSabotageRead)
def update_client(
    client_id: str,
    data: ClientSabotageUpdate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CLIENTS_SABOTAGE_UPDATE)),
):
    client = (
        db.query(ClientSabotage)
        .filter(ClientSabotage.id == client_id, ClientSabotage.tenant_id == current_user.tenant_id)
        .first()
    )
    if not client:
        raise HTTPException(404, "Client introuvable")

    payload = data.model_dump(exclude_unset=True)
    if "telephone" in payload and payload["telephone"] != client.telephone:
        exists = (
            db.query(ClientSabotage)
            .filter(
                ClientSabotage.tenant_id == current_user.tenant_id,
                ClientSabotage.telephone == payload["telephone"],
                ClientSabotage.id != client_id,
            )
            .first()
        )
        if exists:
            raise HTTPException(400, f"Un client avec le téléphone « {payload['telephone']} » existe déjà")

    for key, value in payload.items():
        if key == "extra_fields" and value is not None:
            value = json.dumps(value, ensure_ascii=False)
        setattr(client, key, value)
    db.commit()
    db.refresh(client)
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return client


@router.delete("/{client_id}", response_model=dict)
def delete_client(
    client_id: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.CLIENTS_SABOTAGE_DELETE)),
):
    client = (
        db.query(ClientSabotage)
        .filter(ClientSabotage.id == client_id, ClientSabotage.tenant_id == current_user.tenant_id)
        .first()
    )
    if not client:
        raise HTTPException(404, "Client introuvable")
    db.delete(client)
    db.commit()
    background_tasks.add_task(manager.notify, current_user.tenant_id)
    return {"ok": True}
