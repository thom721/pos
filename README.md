# POS Connect — Système de Caisse Multi-Plateforme

Système de point de vente complet : **backend FastAPI** + **frontend Flutter** multi-plateforme.
Architecture **SaaS multi-tenant** avec support des déploiements **self-hosted** et **mode restaurant**.

---

## Stack technique

| Composant | Technologie |
|-----------|-------------|
| Backend | FastAPI · SQLAlchemy · MySQL / SQLite · Uvicorn |
| Frontend | Flutter 3.x · Riverpod · go_router · Dio |
| Auth | JWT Bearer (python-jose) + FlutterSecureStorage |
| Config | `pos_server.ini` auto-généré + `.env` fallback |
| CI/CD | GitHub Actions |
| Plateformes | Linux · Windows · macOS · Android · Web |

---

## Fonctionnalités

### Commerce (tous types)
- Catalogue produits (catégories, fournisseurs, barcode, images) — `warehouse_id` optionnel par produit
- Caisse POS : ventes, retours, paiements partiels, dettes automatiques
- Achats fournisseurs avec réceptions partielles
- Stock calculé en temps réel (StockMovement)
- Gestion clients et dettes
- **Factures et Devis (Proformas)** : création, impression PDF A4, accès caissier avec permission `invoicesRead`
  - `warehouse_id` optionnel propagé automatiquement des entêtes aux lignes
  - Navigation "Factures / Devis" disponible pour tous les types de commerce (commerce, restaurant, hôtel)

### Restaurant
- Plan de salle : tables avec statut (libre / occupée / réservée)
- Assignation serveur à une ou plusieurs tables — caissiers voient toutes les tables
- Prise de commande par table : recherche plats, notes par article
- Plats du menu avec variantes de prix et flag `send_to_kitchen`
- Sélecteur de dépôt dans le modal plat (affiché si plusieurs dépôts)
- Envoi en cuisine, vue cuisine temps réel
- Encaissement avec couverts, remise et pourboire
- Reçu détaillé à la fermeture de table

### Hôtel (en développement)
- Chambres avec tarif nuitée (`restaurant_tables.price`)
- Attributs personnalisés par chambre (`room_attributes` : clé/valeur)
- Champs check-in configurables (`app_config.hotel_checkin_fields`)

### Administration SaaS
- Multi-tenant : shared (données sur posconnect.ht) ou self-hosted (données chez le client)
- Panel admin : créer/modifier tenants, configurer plans, numéros de paiement, adresse support
- Facturation : essai gratuit → grace period → suspendu → actif
- Synchronisation cloud bidirectionnelle (catalogue) + push (transactions)
- Cache de licence offline Ed25519 (7 jours sans internet)
- Cache SQLite local avec invalidation automatique au changement de tenant/warehouse

---

## Démarrage rapide

### 1. Première installation (serveur)

```bash
cd ~/posconnect
./pos_connect      # Wizard d'installation intégré
```

Le wizard guide :
- Choix du mode (Serveur / Client / Les deux)
- Configuration MySQL ou SQLite
- Vérification d'identité Ed25519 du serveur cloud
- Connexion au compte tenant posconnect.ht

### 2. Lancer le backend manuellement

```bash
./pos_api          # FastAPI sur http://0.0.0.0:8002
# Documentation : http://localhost:8002/docs
```

### 3. Docker (production)

```bash
docker compose up -d --build
docker exec pos_api alembic upgrade head
```

### 4. Client sur une autre machine

```bash
./pos_connect      # → Mode "Client uniquement" → entrer l'URL du serveur
```

---

## Structure du projet

```
pos_api/
├── api/
│   ├── main.py                  # Point d'entrée FastAPI
│   ├── database.py              # Connexion SQLAlchemy + get_db
│   ├── core/
│   │   ├── config.py            # pos_server.ini + .env → Settings
│   │   ├── permissions.py       # Matrice de permissions par rôle
│   │   └── security.py          # JWT create/verify
│   ├── models/                  # SQLAlchemy ORM (22 modèles)
│   │   ├── RestaurantTable.py
│   │   ├── RestaurantOrder.py   # + RestaurantOrderItem
│   │   └── ...
│   ├── routes/
│   │   ├── restaurant.py        # Tables, commandes, checkout
│   │   ├── sales.py
│   │   ├── purchases.py
│   │   └── ...
│   └── alembic/versions/        # Migrations DB
├── frontend/
│   └── lib/
│       ├── core/
│       │   ├── constants.dart   # AppConstants (baseUrl, clé publique Ed25519)
│       │   └── router.dart      # go_router (routes restaurant incluses)
│       ├── data/
│       │   ├── api/api_client.dart      # Dio singleton + extractAnyError
│       │   ├── models/restaurant_model.dart
│       │   └── repositories/restaurant_repository.dart
│       ├── features/
│       │   ├── restaurant/
│       │   │   ├── tables_screen.dart        # Plan de salle
│       │   │   ├── table_order_screen.dart   # Commande + encaissement
│       │   │   └── kitchen_screen.dart       # Vue cuisine
│       │   ├── installer/        # Wizard d'installation
│       │   ├── splash/           # Fast-path si JWT valide
│       │   ├── auth/
│       │   ├── pos/              # Caisse (mode commerce)
│       │   ├── sales/            # Historique ventes + retours
│       │   └── ...
│       ├── providers/
│       │   ├── restaurant_provider.dart
│       │   └── settings_provider.dart   # business_type → navigation adaptative
│       └── shared/widgets/app_shell.dart  # Navigation adaptative par type commerce
├── pos_server.ini               # Config générée par le wizard (non versionné)
├── pos_server.ini.example       # Template de référence
└── requirements.txt
```

---

## Endpoints API principaux

### Setup & Auth
| Méthode | URL | Description |
|---------|-----|-------------|
| GET | `/api/setup/health` | État du serveur + `setup_done` |
| POST | `/api/setup/test-db` | Test credentials DB → écrit `pos_server.ini` |
| POST | `/api/setup/create-db` | Crée la base + tables |
| GET | `/api/public/identity?nonce=` | Signature Ed25519 (vérification identité serveur) |
| POST | `/api/auth/login` | JWT token |

### Métier
| Méthode | URL | Description |
|---------|-----|-------------|
| GET/POST | `/api/products/` | CRUD produits |
| GET/POST | `/api/sales/` | CRUD ventes |
| GET/POST | `/api/purchases/` | CRUD achats |
| GET/POST | `/api/customers/` | CRUD clients |
| GET/POST | `/api/debts/` | Dettes clients/fournisseurs |
| GET | `/api/stock/` | Mouvements de stock |

### Restaurant
| Méthode | URL | Description |
|---------|-----|-------------|
| GET | `/api/restaurant/waiters/` | Liste serveurs disponibles |
| GET/POST | `/api/restaurant/tables/` | Tables (filtrées par rôle `serveur` uniquement) |
| PUT | `/api/restaurant/tables/{id}/assign` | Assigner un serveur |
| GET/POST | `/api/restaurant/menu/` | Plats du menu (tenant-wide, non filtrés par dépôt) |
| GET | `/api/restaurant/orders/table/{id}` | Commande active d'une table |
| POST | `/api/restaurant/orders/` | Ouvrir commande (avec couverts) |
| POST | `/api/restaurant/orders/{id}/checkout` | Encaisser (remise + pourboire) |

### Utilisateurs
| Méthode | URL | Description |
|---------|-----|-------------|
| GET | `/api/users/offline-sync` | Utilisateurs pour auth offline (filtré par `warehouse_id`) |

### SaaS & Billing
| Méthode | URL | Description |
|---------|-----|-------------|
| GET | `/api/billing/license` | Blob de licence signé Ed25519 (cache offline 7j) |
| GET | `/api/billing/caisse-count` | Caisses actives vs plan |
| POST | `/api/sync/token` | Échange credentials → sync token (365j) |
| POST | `/api/admin/tenants` | Créer un tenant (admin) |

---

## Configuration

### pos_server.ini

```ini
[database]
type     = mysql          # mysql | sqlite
host     = localhost
port     = 3306
name     = pos_db
user     = root
password = votre_mot_de_passe

[server]
host                  = 0.0.0.0
port                  = 8002
secret_key            = <généré automatiquement>
token_expire_minutes  = 480
cloud_sync_url        = https://votre-serveur-sync.com
cloud_sync_token      = <sync JWT 365j>
cloud_sync_enabled    = true
billing_url           = https://posconnect.ht
```

### Créer un admin manuellement

```bash
python seed_user.py
# Crée : username=admin / password=Admin@1234
```

### Activer le mode restaurant

Dans l'interface Paramètres > Type de commerce → choisir "Restaurant".
La navigation bascule automatiquement vers : Tables · Cuisine · Ventes · Produits.

### Site public (pages marketing)

Routes publiques accessibles sans auth : `/home`, `/contact`, `/terms`, `/privacy`.
Navigation responsive avec menu hamburger sur mobile (< 860px).
Un refresh navigateur sur une page protégée restaure l'URL d'origine après auth.
Les statistiques du héro (commerces actifs, transactions/jour, disponibilité) sont dynamiques — lues depuis `platform_config` via `/api/public/pricing` et éditables par le superadmin.

---

## Build et distribution

| Plateforme | Artefact |
|------------|----------|
| Linux | `pos_connect-linux.tar.gz` |
| Windows | `pos_connect-windows.zip` |
| macOS | `pos_connect-macos.zip` |
| Android | `pos_connect-android.apk` |

Builds automatiques via GitHub Actions sur chaque push vers `main`.

```bash
# Build APK Android manuellement
cd frontend && flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

# Build web
cd frontend && flutter build web --release \
  --dart-define=SERVER_SCHEME=https \
  --dart-define=SERVER_IP=votre-api.example.com \
  --dart-define=SERVER_PORT=443
```

---

## Développement

```bash
# Backend
python -m uvicorn api.main:app --reload
# Docs : http://127.0.0.1:8002/docs

# Frontend desktop
cd frontend && flutter run -d linux

# Frontend web
cd frontend && flutter run -d chrome

# Migrations
alembic upgrade head
alembic revision --autogenerate -m "description"
```
