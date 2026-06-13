from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from api.services.auth_service import AuthService
from sqlalchemy.orm import Session
from api.models.User import User
from api.database import get_db

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/login")

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    auth_service = AuthService(db)
    payload = auth_service.verify_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid token")
    user_id = payload.get("sub")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

# from fastapi import APIRouter, Depends
# from dependencies.auth import get_current_user
# from sqlalchemy.orm import Session
# from database import get_db
# from models import User

# router = APIRouter(prefix="/users", tags=["users"])

# @router.get("/me")
# def read_current_user(current_user: User = Depends(get_current_user)):
#     return current_user

# @router.get("/")
# def list_users(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
#     return db.query(User).all()

