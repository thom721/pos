# POS API — Point of Sale REST API

API backend pour un système de caisse (Point of Sale) développée avec **FastAPI**, **SQLAlchemy** et **MySQL**.

---

## Stack technique

| Composant     | Technologie             |
|---------------|-------------------------|
| Framework     | FastAPI 0.127           |
| ORM           | SQLAlchemy 2.0          |
| Base de données | MySQL (PyMySQL)       |
| Migrations    | Alembic 1.17            |
| Auth          | JWT (PyJWT / python-jose)|
| Validation    | Pydantic v2             |
| Serveur       | Uvicorn                 |
| Python        | 3.11                    |

---

## Structure du projet

```
pos_api/
├── api/
│   ├── main.py                  # Point d'entrée FastAPI
│   ├── database.py              # Connexion SQLAlchemy + get_db
│   ├── alembic.ini              # Config migrations
│   ├── core/
│   │   ├── config.py            # Settings (SECRET_KEY, JWT config)
│   │   ├── security.py          # create_access_token / verify_token
│   │   └── PaginateHelper.py    # Helper pagination générique
│   ├── models/
│   │   ├── base.py              # UUIDBase (id UUID, created_at, updated_at)
│   │   ├── User.py              # Utilisateurs (roles JSON, permissions JSON)
│   │   ├── Category.py          # Catégories produits
│   │   ├── Supplier.py          # Fournisseurs
│   │   ├── Product.py           # Produits (stock calculé via StockMovement)
│   │   ├── Customer.py          # Clients
│   │   ├── Sale.py              # Ventes (UNPAID / PAID / PARTIAL / credit)
│   │   ├── SaleItem.py          # Lignes de vente
│   │   ├── Purchase.py          # Achats fournisseurs (pending / partial / paid)
│   │   ├── PurchaseItem.py      # Lignes d'achat (ordered_qty, remaining_qty)
│   │   ├── PurchaseReceipt.py   # Réceptions de commande
│   │   ├── PurchaseReceiptItem.py # Lignes de réception
│   │   ├── StockMovement.py     # Mouvements de stock (in / out / adjust)
│   │   ├── Payment.py           # Paiements (SALE ou PURCHASE)
│   │   └── Debt.py              # Dettes clients/fournisseurs
│   ├── schemas/
│   │   ├── user.py              # UserCreate, UserRead
│   │   ├── product.py           # ProductCreate, ProductRead
│   │   ├── category.py          # CategoryCreate, CategoryRead
│   │   ├── supplier.py          # SupplierCreate, SupplierRead
│   │   ├── customer.py          # CustomerCreate, CustomerRead
│   │   ├── sale.py              # SaleCreate, SaleItemInput, ProductSaleItem
│   │   ├── purchase.py          # PurchaseCreate, PurchaseRead, PurchaseItemRead
│   │   ├── purchase_receipt.py  # PurchaseReceiptCreate
│   │   ├── purchase_item_receipt.py
│   │   ├── SaleReturnItem.py    # SaleReturnPayload, PurchaseReturnPayload
│   │   ├── stock.py             # StockMovementRead
│   │   ├── login.py             # LoginRequest
│   │   └── common.py           # PaginatedResponse générique
│   ├── routes/
│   │   ├── auth.py              # POST /api/auth/login → JWT token
│   │   ├── user.py              # CRUD utilisateurs
│   │   ├── category.py          # CRUD catégories
│   │   ├── supplier.py          # CRUD fournisseurs
│   │   ├── product.py           # CRUD produits
│   │   ├── customer.py          # CRUD clients
│   │   ├── sales.py             # POST /api/sales/, GET /api/sales/products
│   │   ├── purchases.py         # CRUD /api/purchases/
│   │   ├── purchases_receive.py # POST réception commande
│   │   ├── stock.py             # GET mouvements de stock
│   │   └── returns.py           # POST retour vente / achat
│   ├── services/
│   │   ├── auth.py              # Classe Auth (authenticate_user, create_access_token)
│   │   ├── auth_service.py      # AuthService (verify_token)
│   │   ├── sale_service.py      # create_sale, cancel_sale
│   │   ├── purchase_service.py  # create_purchase, list_purchases, get_purchase
│   │   ├── ReceiptService.py    # Réception partielle/complète de commande
│   │   ├── return_service.py    # process_sale_return, process_purchase_return
│   │   ├── stock_service.py     # list_stock_movements
│   │   ├── product_service.py   # ProductService (list avec pagination)
│   │   ├── category_service.py
│   │   ├── supplier_service.py
│   │   ├── customer_service.py
│   │   ├── debt_service.py
│   │   └── user_service.py
│   ├── dependencies/
│   │   ├── auth.py              # get_current_user (JWT Bearer)
│   │   └── refresh_auth.py
│   └── utils/
│       └── Validator.py
├── alembic/                     # Migrations racine (doublon)
├── requirements.txt
└── pyvenv.cfg
```

---

## Modèle de données

### Relations principales

```
User ──────────────────────── Sale (user_id)
                               └── SaleItem (product_id)
                               └── Payment (reference_type=SALE)
                               └── Debt (reference_type=SALE)

User ──────────────────────── Purchase (user_id)
                               └── PurchaseItem (product_id)
                                   └── PurchaseReceiptItem
                               └── PurchaseReceipt
                               └── Payment (reference_type=PURCHASE)
                               └── Debt (reference_type=PURCHASE)

Product ── Category
        ── Supplier
        ── StockMovement[]    (stock = somme des mouvements)

Customer ── Sale[]
Supplier ── Purchase[]
```

### Statuts

| Entité    | Statuts possibles                          |
|-----------|--------------------------------------------|
| Sale      | UNPAID / PAID / PARTIAL / credit / pending |
| Purchase  | pending / partial / paid                   |
| Debt      | UNPAID / PARTIAL / PAID                    |
| StockType | in / out / adjust                          |
| Payment   | CASH / BANK / MOBILE                       |

---

## Endpoints disponibles

| Méthode | URL                           | Description                        |
|---------|-------------------------------|------------------------------------|
| POST    | `/api/auth/login`             | Authentification → JWT token       |
| GET/POST| `/api/users/`                 | Gestion utilisateurs               |
| GET/POST| `/api/categories/`            | Gestion catégories                 |
| GET/POST| `/api/suppliers/`             | Gestion fournisseurs               |
| GET/POST| `/api/products/`              | Gestion produits                   |
| GET/POST| `/api/customers/`             | Gestion clients                    |
| POST    | `/api/sales/`                 | Créer une vente                    |
| GET     | `/api/sales/products`         | Recherche produits pour la caisse  |
| GET/POST| `/api/purchases/`             | Gestion achats fournisseurs        |
| GET     | `/api/purchases/{id}`         | Détail d'un achat                  |
| POST    | `/api/purchases/receive`      | Réceptionner une commande          |
| GET     | `/api/stock/`                 | Mouvements de stock                |
| POST    | `/returns/sale`               | Retour client                      |
| POST    | `/returns/purchase`           | Retour fournisseur                 |

---

## Lancer le projet

```bash
# Activer l'environnement virtuel
source bin/activate

# Lancer le serveur de développement
python -m uvicorn api.main:app --reload

# Accès documentation interactive
# http://127.0.0.1:8000/docs
```

---

## Configuration

Le projet utilise un fichier `.env` (à créer à la racine) :

```env
SECRET_KEY=your_secret_key_here
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7
DATABASE_URL=mysql+pymysql://user:password@localhost:3306/pos_db
```

---

## Logique métier

### Vente (Sale)
1. Vérification stock disponible pour chaque produit
2. Calcul du total avec remise (discount)
3. Création de la vente + lignes (SaleItem)
4. Mouvement stock OUT par produit
5. Enregistrement paiement (Payment)
6. Création dette (Debt) si solde restant > 0
7. Mise à jour statut (PAID / PARTIAL / UNPAID)

### Achat (Purchase)
1. Calcul total commande
2. Création achat + lignes (PurchaseItem avec ordered_qty)
3. Paiement partiel ou total possible
4. Réception séparée via PurchaseReceipt (stock IN à la réception)
5. Statut auto : pending → partial → paid selon réception

### Stock
- Le stock d'un produit = somme des `StockMovement.quantity`
- Aucune colonne `stock` directe sur Product
- Sources : purchase_receipt, sale, sale_return, purchase_return, adjust
# pos
