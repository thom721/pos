from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from passlib.context import CryptContext
from sqlalchemy.orm import Session
from api.models.User import User
from api.core.config import settings
from fastapi import HTTPException
from pwdlib import PasswordHash

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class AuthService:
    def __init__(self, db: Session):
        self.db = db
        self.password_hash = PasswordHash.recommended()
        # openssl rand -hex 32
        # SECRET_KEY = "09d25e094faa6ca2556c818166b7a9563b93f7099f6f0f4caa6cf63b88e8d3e7"
        # ALGORITHM = "HS256"
        # ACCESS_TOKEN_EXPIRE_MINUTES = 30

    # 🔐 Password
    # def verify_password(self, plain, hashed): 
    #     return pwd_context.verify(plain[:72], hashed)

    # def hash_password22(self, password):
    #     return pwd_context.hash(password[:70])

    # def hash_password(self,password: str) -> str:
    #     hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
    #     return hashed.decode("utf-8").replace("$2b$", "$2y$")
    
    
    def verify_password(self,plain_password, hashed_password):
        return self.password_hash.verify(plain_password, hashed_password)


    def get_password_hash(self,password):
        return self.password_hash.hash(password)

    # 🔑 Tokens
    def create_access_token(self, user_id: str):
        payload = {
            "sub": user_id,
            "exp": datetime.now(timezone.utc) + timedelta(minutes=30)
        }
        return jwt.encode(payload, settings.SECRET_KEY, algorithm="HS256")

    def create_refresh_token(self, user_id: str):
        payload = {
            "sub": user_id,
            "exp": datetime.now(timezone.utc) + timedelta(days=7)
        }
        return jwt.encode(payload, settings.SECRET_KEY, algorithm="HS256")

    def verify_token(self, token: str):
        try:
            return jwt.decode(token, settings.SECRET_KEY, algorithms=["HS256"])
        except JWTError:
            return None
