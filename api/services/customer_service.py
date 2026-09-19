import re
from typing import List, Optional
from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from api.models.Customer import Customer
from api.schemas.customer import CustomerCreate, CustomerUpdate
from api.services.base_service import TenantService

_UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', re.I)


class CustomerService(TenantService):
    def __init__(self, db: Session, tenant_id: str | None = None):
        super().__init__(db, tenant_id)

    def create(self, data: CustomerCreate) -> Customer:
        # Idempotence hors-ligne : ce client_id existe déjà (retry après une
        # synchro déjà réussie) → renvoyer l'existant directement, ce n'est
        # pas une nouvelle création, donc pas de vérification de doublon de
        # nom à faire ici.
        if data.client_id and _UUID_RE.match(data.client_id):
            existing = self.db.query(Customer).filter_by(id=data.client_id).first()
            if existing:
                return existing

        # Aucune contrainte d'unicité nom+prénom en base — avertir avant de
        # créer un doublon plutôt que de laisser la liste grossir en
        # silence. JAMAIS bloquant pour un item rejoué depuis la file
        # hors-ligne (confirm_duplicate y est toujours vrai côté client —
        # aucune confirmation interactive n'est possible en arrière-plan ;
        # bloquer indéfiniment laisserait l'opération ne jamais synchroniser,
        # exactement la classe de bug corrigée plus tôt — voir l'incident du
        # 2026-09-19, session restée ouverte 10 jours + ventes bloquées).
        if not data.confirm_duplicate:
            fname_norm = (data.fname or '').strip().lower()
            name_norm = (data.name or '').strip().lower()
            dup = self._q(Customer).filter(
                func.lower(func.trim(Customer.fname)) == fname_norm,
                func.lower(func.trim(Customer.name)) == name_norm,
            ).first()
            if dup:
                raise HTTPException(409, {
                    "duplicate": True,
                    "message": f'Un client nommé "{dup.full_name}" existe déjà.',
                    "existing_customer_id": dup.id,
                    "existing_customer_name": dup.full_name,
                    "existing_customer_phone": dup.phone,
                })

        customer = Customer(**data.dict(exclude={'client_id', 'confirm_duplicate'}))
        self._set_tenant(customer)
        # UUID généré par le client (offline-first) — voir create_sale, même
        # mécanisme : sans ça, un client créé hors-ligne recevait un id
        # serveur totalement différent de celui déjà utilisé (et figé) par
        # la vente créée dans la foulée, qui ne pouvait alors plus jamais
        # synchroniser (client_id introuvable, erreur de clé étrangère
        # définitive — voir l'incident du 2026-09-19).
        if data.client_id and _UUID_RE.match(data.client_id):
            customer.id = data.client_id
        self.db.add(customer)
        try:
            self.db.commit()
        except IntegrityError:
            self.db.rollback()
            # client_id déjà utilisé (retry après une synchro déjà réussie) →
            # retourner le client existant plutôt qu'échouer (idempotence).
            if data.client_id:
                existing = self.db.query(Customer).filter_by(id=data.client_id).first()
                if existing:
                    return existing
            raise
        self.db.refresh(customer)
        return customer

    def get(self, customer_id: str) -> Optional[Customer]:
        return self._q(Customer).filter(Customer.id == customer_id).first()

    def list(self) -> List[Customer]:
        return self._q(Customer).all()

    def update(self, customer_id: str, data: CustomerUpdate) -> Optional[Customer]:
        customer = self.get(customer_id)
        if not customer:
            return None
        for field, value in data.dict(exclude_unset=True).items():
            setattr(customer, field, value)
        self.db.commit()
        self.db.refresh(customer)
        return customer

    def delete(self, customer_id: str) -> bool:
        customer = self.get(customer_id)
        if not customer:
            return False
        self.db.delete(customer)
        self.db.commit()
        return True
