from fastapi import Depends, HTTPException
from api.models import User
from sqlalchemy.orm import Session
from api.database import get_db
# alembic upgrade head

def get_current_user(db: Session = Depends(get_db)):
    # Ici tu récupères l'utilisateur connecté via JWT ou session
    # Exemple simple (à adapter selon ton auth):
    user = db.query(User).first()  # <- juste pour test
    if not user:
        raise HTTPException(401, "Utilisateur non authentifié")
    return user
