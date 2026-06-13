from datetime import datetime, timedelta, timezone
from typing import Annotated

from jose import jwt
from fastapi import HTTPException
from pwdlib import PasswordHash
from pydantic import BaseModel
# from api.schemas.user import UserOut
from api.models.User import User as Out

from api.core.config import settings
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = settings.ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES




class Token(BaseModel):
    access_token: str
    token_type: str
    user: dict


class TokenData(BaseModel):
    username: str | None = None

# class UserInDB(Out):
#     password: str

def get_password_hash(password):
    password_hash = PasswordHash.recommended()
    return password_hash.hash(password)

class Auth:
    def __init__(self, db):
        self.db = db
        self.password_hash = PasswordHash.recommended() 

    def verify_password(self,plain_password, hashed_password):
        return self.password_hash.verify(plain_password, hashed_password)


    def get_password_hash(self,password):
        return self.password_hash.hash(password)


    def get_user(self, username: str):
        return self.db.query(Out).filter(Out.username == username).first()


    def authenticate_user(self, username: str, password: str):
        try:
            user = self.get_user(username)
            if not user or not self.verify_password(password, user.password):
                return None
            return user 
        except Exception as e:
            import traceback
            traceback.print_exc()
            print(f"___________ → {e}")
            raise HTTPException(status_code=500, detail=str(e))



    def create_access_token(self,data: dict, expires_delta: timedelta | None = None):
        to_encode = data.copy()
        if expires_delta:
            expire = datetime.now(timezone.utc) + expires_delta
        else:
            expire = datetime.now(timezone.utc) + timedelta(minutes=15)
        to_encode.update({"exp": expire})
        encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
        return encoded_jwt





    # async def get_current_active_user(
    #     current_user: Annotated[User, Depends(get_current_user)],
    # ):
    #     if current_user.disabled:
    #         raise HTTPException(status_code=400, detail="Inactive user")
    #     return current_user
