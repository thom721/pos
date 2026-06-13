# PPRD — Product & Project Requirements Document
# POS API — Système de Caisse FastAPI

**Date :** 2026-06-10
**Version :** 0.1 (en développement)
**Stack :** Python 3.11 · FastAPI · SQLAlchemy · MySQL · JWT

---

## 1. Vue d'ensemble du projet

API REST pour un logiciel de point de vente (POS) destiné à gérer les ventes, achats, stock, clients, fournisseurs et paiements. Consommé par une interface desktop (PySide6/Python GUI) ou web.

---

## 2. Fonctionnalités implémentées

### 2.1 Authentification
- [x] Login username/password → JWT Bearer token
- [x] Middleware `get_current_user` via OAuth2PasswordBearer
- [x] Roles et permissions stockés en JSON dans le modèle User

### 2.2 Catalogue
- [x] CRUD Catégories
- [x] CRUD Produits (avec barcode, prix d'achat, prix de vente, seuil d'alerte)
- [x] CRUD Fournisseurs
- [x] Recherche produits avec pagination (pour la caisse)

### 2.3 Clients
- [x] CRUD Clients (nom, téléphone, email, adresse, limite de crédit)

### 2.4 Ventes
- [x] Création vente avec lignes (SaleItem)
- [x] Vérification stock avant vente
- [x] Mouvements stock OUT automatiques
- [x] Enregistrement paiement
- [x] Création dette automatique si paiement partiel
- [x] Statuts : UNPAID / PAID / PARTIAL
- [x] Annulation de vente (cancel_sale)
- [x] Retour client (process_sale_return)

### 2.5 Achats fournisseurs
- [x] Création commande achat avec lignes
- [x] Paiement partiel/total à la commande
- [x] Réception partielle ou totale (PurchaseReceipt)
- [x] Mouvements stock IN à la réception
- [x] Statuts : pending / partial / paid
- [x] Retour fournisseur (process_purchase_return)
- [x] Liste avec filtres (search, status, date)

### 2.6 Stock
- [x] Stock calculé via somme des StockMovement (pas de champ direct)
- [x] Types : in / out / adjust
- [x] Historique des mouvements avec filtres et pagination

### 2.7 Paiements et Dettes
- [x] Modèle Payment polymorphique (SALE ou PURCHASE)
- [x] Modèle Debt avec partner (CUSTOMER ou SUPPLIER)
- [x] Méthodes paiement : CASH / BANK / MOBILE

### 2.8 Infrastructure
- [x] UUIDs pour toutes les entités (pas d'auto-increment)
- [x] Timestamps automatiques `created_at` / `updated_at` sur toutes les tables
- [x] Pagination générique (PaginateHelper / PaginatedResponse)
- [x] Gestion centralisée des erreurs (422, 401, 500)
- [x] Alembic configuré pour les migrations

---

## 3. Ce qui MANQUE — Bugs et lacunes critiques

### 3.1 Bugs bloquants

| # | Fichier | Problème |
|---|---------|----------|
| B1 | `api/models/Sale.py` | Le champ `paid_amount` est absent du modèle Sale mais utilisé dans `sale_service.py` (ligne 51, 80, 93) → AttributeError en production |
| B2 | `api/models/Sale.py` | `balance` hybrid property référence `self.paid_amount` qui n'existe pas |
| B3 | `api/models/Customer.py` | `balance` hybrid property référence `s.paid_amount` sur Sale → même bug |
| B4 | `api/services/return_service.py` | Utilise `sale.paid_amount` et `purchase.quantity` qui n'existent pas |
| B5 | `api/services/ReceiptService.py` | `type="in_"` envoyé à StockMovement alors que l'enum attend `"in"` (avec underscore uniquement sur le nom Python, pas la valeur) |
| B6 | `api/models/Debt.py` | `reference_type` enum accepte 'SALE' et 'PURCHASE' mais `Customer.debts` filtre sur `reference_type == 'CUSTOMER'` → la relation ne fonctionne jamais |
| B7 | `api/routes/sales.py` | `user_id: str = "USER_UUID_Ici"` — authentification désactivée, toutes les ventes sont attribuées à une chaîne fictive |
| B8 | `api/services/sale_service.py` | `'Cassier' in user.permission` : faute de frappe (`permission` vs `permissions`) et vérification non implémentée dans la vraie fonction `create_sale` |
| B9 | `api/core/security.py` | `SECRET_KEY = "SUPER_SECRET_KEY"` hardcodé — différent de la clé dans `dependencies/auth.py` → tokens invalides entre modules |

### 3.2 Sécurité

| # | Problème | Impact |
|---|----------|--------|
| S1 | `database.py` : mot de passe MySQL `@#1900` hardcodé en clair | Credentials exposés dans le code source |
| S2 | `SECRET_KEY` JWT défini à 3 endroits différents (`security.py`, `dependencies/auth.py`, `routes/auth.py`) avec des valeurs différentes | Tokens signés avec une clé, vérifiés avec une autre |
| S3 | `config.py` utilise `SECRET_KEY = "CHANGE_ME"` mais aucun fichier `.env` n'est fourni | Déploiement avec clé non sécurisée |
| S4 | Aucune validation que `reference_type` du Payment correspond au bon type en base | Paiement croisé possible (payer une vente comme un achat) |

### 3.3 Fonctionnalités manquantes

| # | Feature | Priorité |
|---|---------|----------|
| F1 | `GET /api/sales/` — liste des ventes avec filtres et pagination | Haute |
| F2 | `GET /api/sales/{id}` — détail d'une vente | Haute |
| F3 | `SaleRead` schema Pydantic — réponse structurée pour les ventes | Haute |
| F4 | Endpoint paiement additionnel : `POST /api/payments/` — ajouter un paiement à une vente ou achat existant | Haute |
| F5 | `GET /api/debts/` — liste des dettes clients et fournisseurs | Haute |
| F6 | Dashboard / statistiques : total ventes, chiffre d'affaires, bénéfice brut | Moyenne |
| F7 | `PATCH /api/sales/{id}/cancel` — annulation de vente depuis l'API | Moyenne |
| F8 | `GET /api/products/{id}/stock` — niveau de stock d'un produit | Moyenne |
| F9 | Gestion des alertes stock (produits sous le seuil `alert_stock`) | Moyenne |
| F10 | Champ `is_active` sur User (présent dans les commentaires mais absent du modèle) | Basse |
| F11 | Refresh token endpoint | Basse |

### 3.4 Code à nettoyer

| # | Fichier | Problème |
|---|---------|----------|
| C1 | `api/services/sale_service.py` | 4 versions de `create_sale` coexistent : `create_sale`, `create_sale1`, `create_sale33`, `process_sale_payment` → code mort |
| C2 | `api/services/purchase_service.py` | `create_purchase1111` — version abandonnée toujours présente |
| C3 | `api/dependencies/auth copy.py` | Fichier backup "auth copy.py" dans le code source |
| C4 | `api/routes/login copy.py` | Fichier backup "login copy.py" dans le code source |
| C5 | `api/schemas/login copy.py` | Idem |
| C6 | `api/main.py` | ~100 lignes de notes PostgreSQL/MongoDB en commentaires en bas de fichier |
| C7 | `api/database.py` | ~40 lignes de notes d'installation MongoDB en commentaires |
| C8 | `api/dependencies/auth.py` | `get_current_user22222` et `get_current_usereee` — fonctions abandonnées avec numéros |
| C9 | Dossier `alembic/` à la racine + `api/alembic/` | Double configuration Alembic — risque de confusion |

### 3.5 Configuration et déploiement

| # | Problème |
|---|----------|
| D1 | Pas de fichier `.env.example` — impossible de configurer l'environnement sans lire le code |
| D2 | L'environnement virtuel (`bin/`, `lib/`, `include/`) est dans le répertoire projet → doit être exclu |
| D3 | Pas de `.gitignore` — le venv sera commité par accident |
| D4 | Pas de `Dockerfile` ni `docker-compose.yml` |
| D5 | `DATABASE_URL` hardcodée dans `database.py`, pas lue depuis `.env` |

### 3.6 Tests

| # | Problème |
|---|----------|
| T1 | Aucun fichier de test dans le projet |
| T2 | Pas de `pytest` dans `requirements.txt` |
| T3 | Pas de fixtures pour la base de données de test |

---

## 4. Priorités de correction recommandées

### Phase 1 — Corrections bloquantes (à faire maintenant)

1. **Ajouter `paid_amount` au modèle Sale** (B1, B2, B3, B4)
2. **Unifier la SECRET_KEY** — lire depuis `config.py` / `.env` partout (S2, S3)
3. **Corriger le bug `reference_type == 'CUSTOMER'`** dans Debt/Customer (B6)
4. **Activer l'auth JWT sur `/api/sales/`** (B7)
5. **Corriger `type="in_"` → `type="in"` dans ReceiptService** (B5)

### Phase 2 — Fonctionnalités essentielles

6. **Créer `SaleRead` schema et `GET /api/sales/`** (F1, F2, F3)
7. **Endpoint paiement additionnel** (F4)
8. **Endpoint liste dettes** (F5)
9. **Déplacer DATABASE_URL dans `.env`** (D5)
10. **Créer `.env.example` et `.gitignore`** (D1, D3)

### Phase 3 — Nettoyage et qualité

11. Supprimer le code mort (C1–C9)
12. Ajouter les tests unitaires de base (T1–T3)
13. Dashboard/statistiques (F6)

---

## 5. Schéma de base de données cible

```
users           categories      suppliers
  │                │               │
  │           products ────────────┘
  │               │
  ├── sales ──────┤
  │     └── sale_items
  │     └── payments (reference_type=SALE)
  │     └── debts   (reference_type=SALE)
  │
  └── purchases ──┤
        └── purchase_items
              └── purchase_receipt_items
        └── purchase_receipts
        └── payments (reference_type=PURCHASE)
        └── debts   (reference_type=PURCHASE)

stock_movements ← lié à Product + User + source (sale/purchase/adjust)
```
