"""
Script pour créer un utilisateur admin dans la base de données.
Usage : python seed_user.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from api.database import SessionLocal, engine
from api.models.base import UUIDBase
# Import all models so SQLAlchemy resolves every relationship
import api.models.Category
import api.models.Customer
import api.models.Supplier
import api.models.Product
import api.models.StockMovement
import api.models.Sale
import api.models.SaleItem
import api.models.Purchase
import api.models.PurchaseItem
import api.models.PurchaseReceipt
import api.models.PurchaseReceiptItem
import api.models.Payment
import api.models.Debt
from api.models.User import User
from pwdlib import PasswordHash

_hasher = PasswordHash.recommended()

USER_DATA = {
    "fname":      "Admin",
    "lname":      "POS",
    "username":   "admin",
    "phone":      "50900000000",
    "address":    "Port-au-Prince, Haïti",
    "email":      "admin@posconnect.ht",
    "roles":      ["admin"],
    "permissions": ["all"],
    "password":   "Admin@1234",
}

def create_tables():
    UUIDBase.metadata.create_all(bind=engine)
    print("✓ Tables créées (ou déjà existantes).")

def seed():
    db = SessionLocal()
    try:
        existing = db.query(User).filter(User.username == USER_DATA["username"]).first()
        if existing:
            print(f"[INFO] L'utilisateur '{USER_DATA['username']}' existe déjà.")
            print(f"       Username : {existing.username}")
            print(f"       Mot de passe : {USER_DATA['password']}")
            return

        user = User(
            fname=USER_DATA["fname"],
            lname=USER_DATA["lname"],
            username=USER_DATA["username"],
            phone=USER_DATA["phone"],
            address=USER_DATA["address"],
            email=USER_DATA["email"],
            roles=USER_DATA["roles"],
            permissions=USER_DATA["permissions"],
            password=_hasher.hash(USER_DATA["password"]),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        print("✓ Utilisateur créé avec succès !")
        print(f"  Username  : {user.username}")
        print(f"  Mot de passe : {USER_DATA['password']}")
        print(f"  ID        : {user.id}")
    except Exception as e:
        db.rollback()
        print(f"[ERREUR] {e}")
        raise
    finally:
        db.close()

if __name__ == "__main__":
    create_tables()
    seed()
