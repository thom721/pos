from pydantic import BaseModel, EmailStr 

# ===== Login =====
class LoginSchema(BaseModel):
    email: EmailStr
    password: str

class TokenSchema(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"

class RefreshTokenSchema(BaseModel):
    refresh_token: str
