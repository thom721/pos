"""
Script pour insérer des données de test :
  - 3 catégories
  - 2 fournisseurs
  - 3 clients
  - 10 produits (avec stock initial)
Usage : python3 seed_data.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

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
import api.models.User

from api.database import SessionLocal
from api.models.Category import Category
from api.models.Customer import Customer
from api.models.Supplier import Supplier
from api.models.Product import Product
from api.models.StockMovement import StockMovement, StockType

# ──────────────────────────────────────────────
# DONNÉES
# ──────────────────────────────────────────────

CATEGORIES = [
    {"name": "Alimentation",        "cat_description": "Produits alimentaires et boissons"},
    {"name": "Hygiène & Beauté",    "cat_description": "Soins personnels et cosmétiques"},
    {"name": "Électronique",        "cat_description": "Appareils électroniques et accessoires"},
]

SUPPLIERS = [
    {
        "name":    "Distributeur Caraïbes",
        "phone":   "50936000001",
        "email":   "contact@distcaraibes.ht",
        "address": "Route Nationale #1, Port-au-Prince",
    },
    {
        "name":    "Import Tech Haïti",
        "phone":   "50936000002",
        "email":   "info@importtech.ht",
        "address": "Blvd Toussaint Louverture, Pétionville",
    },
]

CUSTOMERS = [
    {
        "name":         "Marie Jean-Baptiste",
        "phone":        "50934100001",
        "email":        "marie.jb@email.com",
        "address":      "Rue Capois, Port-au-Prince",
        "credit_limit": 5000.00,
    },
    {
        "name":         "Pierre Augustin",
        "phone":        "50934100002",
        "email":        None,
        "address":      "Delmas 75, Port-au-Prince",
        "credit_limit": 2500.00,
    },
    {
        "name":         "Claudette Moreau",
        "phone":        "50934100003",
        "email":        "claudette.m@gmail.com",
        "address":      "Carrefour-Feuilles, Port-au-Prince",
        "credit_limit": 8000.00,
    },
]

# (name, barcode, purchase_price, sale_price, alert_stock, description, category_key, stock_initial)
PRODUCTS = [
    ("Riz Blanc 5kg",         "6001001", 350.00, 450.00, 10, "Riz blanc long grain 5 kg",         "Alimentation",     50),
    ("Huile Végétale 1L",     "6001002", 120.00, 160.00,  8, "Huile végétale 1 litre",             "Alimentation",     40),
    ("Sucre Blanc 1kg",       "6001003",  60.00,  85.00, 15, "Sucre cristallisé blanc 1 kg",       "Alimentation",     60),
    ("Farine de Blé 2kg",     "6001004",  95.00, 130.00, 10, "Farine de blé tout usage 2 kg",      "Alimentation",     35),
    ("Eau Minérale 1.5L",     "6001005",  30.00,  50.00, 20, "Eau minérale en bouteille 1.5 L",    "Alimentation",     80),
    ("Savon de Toilette",     "6002001",  25.00,  45.00, 10, "Savon de bain 100 g",                "Hygiène & Beauté", 70),
    ("Shampooing 400ml",      "6002002",  90.00, 140.00,  5, "Shampooing hydratant 400 ml",        "Hygiène & Beauté", 30),
    ("Dentifrice 100ml",      "6002003",  55.00,  85.00,  8, "Pâte dentifrice menthe 100 ml",      "Hygiène & Beauté", 45),
    ("Chargeur USB-C",        "6003001", 200.00, 350.00,  3, "Chargeur rapide USB-C 25W",          "Électronique",     20),
    ("Écouteurs Bluetooth",   "6003002", 450.00, 750.00,  2, "Écouteurs sans fil Bluetooth 5.0",  "Électronique",     15),
]


def seed():
    db = SessionLocal()
    try:
        # ── Catégories ──
        cat_map = {}
        for c in CATEGORIES:
            existing = db.query(Category).filter(Category.name == c["name"]).first()
            if existing:
                cat_map[c["name"]] = existing
                print(f"  [skip] Catégorie '{c['name']}' existe déjà")
            else:
                obj = Category(**c)
                db.add(obj)
                db.flush()
                cat_map[c["name"]] = obj
                print(f"  ✓ Catégorie '{c['name']}' créée")

        # ── Fournisseurs ──
        sup_list = []
        for s in SUPPLIERS:
            existing = db.query(Supplier).filter(Supplier.phone == s["phone"]).first()
            if existing:
                sup_list.append(existing)
                print(f"  [skip] Fournisseur '{s['name']}' existe déjà")
            else:
                obj = Supplier(**s)
                db.add(obj)
                db.flush()
                sup_list.append(obj)
                print(f"  ✓ Fournisseur '{s['name']}' créé")

        # ── Clients ──
        for c in CUSTOMERS:
            existing = db.query(Customer).filter(Customer.phone == c["phone"]).first()
            if existing:
                print(f"  [skip] Client '{c['name']}' existe déjà")
            else:
                obj = Customer(**c)
                db.add(obj)
                print(f"  ✓ Client '{c['name']}' créé")

        db.flush()

        # ── Produits + stock initial ──
        # Récupère un user quelconque pour les mouvements de stock
        from api.models.User import User
        user = db.query(User).first()
        user_id = user.id if user else None

        for (name, barcode, pp, sp, alert, desc, cat_name, stock_init) in PRODUCTS:
            existing = db.query(Product).filter(Product.name == name).first()
            if existing:
                print(f"  [skip] Produit '{name}' existe déjà")
                continue

            cat = cat_map.get(cat_name)
            if not cat:
                print(f"  [warn] Catégorie '{cat_name}' introuvable pour '{name}'")
                continue

            prod = Product(
                name=name,
                barcode=barcode,
                purchase_price=pp,
                sale_price=sp,
                alert_stock=alert,
                description=desc,
                category_id=cat.id,
                is_active=True,
            )
            db.add(prod)
            db.flush()

            # Mouvement stock initial
            if stock_init > 0:
                db.add(StockMovement(
                    product_id=prod.id,
                    user_id=user_id,
                    type=StockType.in_,
                    quantity=stock_init,
                    source_type="INITIAL",
                    source_id=prod.id,
                    note="Stock initial",
                ))

            print(f"  ✓ Produit '{name}' créé (stock: {stock_init})")

        db.commit()
        print("\n✓ Toutes les données ont été insérées avec succès.")

    except Exception as e:
        db.rollback()
        import traceback; traceback.print_exc()
        print(f"\n[ERREUR] {e}")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
