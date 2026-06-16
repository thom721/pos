# POS Connect — Système de Caisse Multi-Plateforme

Système de point de vente complet : **backend FastAPI** + **frontend Flutter** multi-plateforme.
Architecture **SaaS multi-tenant** avec support des déploiements **self-hosted** (données hébergées chez le client).

---

## Stack technique

| Composant | Technologie |
|-----------|-------------|
| Backend | FastAPI · SQLAlchemy · MySQL / SQLite · Uvicorn |
| Frontend | Flutter 3.x · Riverpod · go_router · Dio |
| Auth | JWT Bearer (python-jose) |
| Config | `pos_server.ini` auto-généré + `.env` fallback |
| CI/CD | GitHub Actions |
| Plateformes | Linux · Windows · macOS · Android · Web |

---

## Démarrage rapide

### 1. Serveur (première installation)

```bash
cd ~/posconnect
./pos_connect      # Wizard d'installation intégré
```

Le wizard guide pas à pas :
- Choix du mode (Serveur / Client / Les deux)
- Configuration MySQL ou SQLite
- Vérification d'identité Ed25519 du serveur cloud
- Connexion au compte tenant posconnect.ht (shared ou self-hosted)
- Génération automatique de `pos_server.ini` avec `cloud_sync_url` et `billing_url`

### 2. Lancer le backend manuellement

```bash
cd ~/posconnect
./pos_api          # FastAPI sur http://0.0.0.0:8002
```

### 3. Client sur une autre machine

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
│   │   └── security.py          # JWT create/verify
│   ├── models/                  # SQLAlchemy ORM (19 modèles)
│   ├── schemas/                 # Pydantic v2
│   ├── routes/
│   │   ├── setup.py             # Wizard API (health, test-db, create-db, init)
│   │   ├── auth.py
│   │   ├── sales.py
│   │   ├── purchases.py
│   │   └── ...
│   └── services/
├── frontend/                    # Application Flutter (pos_connect)
│   └── lib/
│       ├── main.dart
│       ├── core/
│       │   ├── constants.dart   # AppConstants (baseUrl défaut)
│       │   └── router.dart      # go_router
│       ├── data/api/
│       │   └── api_client.dart  # Dio singleton + initServerUrl()
│       └── features/
│           ├── installer/       # Wizard d'installation complet
│           ├── splash/          # Détection setup_done
│           ├── auth/
│           ├── pos/
│           ├── products/
│           └── ...
├── pos_server.ini               # Config générée par le wizard
├── pos_server.ini.example       # Template de référence
├── requirements.txt
└── seed_user.py                 # Créer un utilisateur admin manuellement
```

---

## Endpoints API principaux

| Méthode | URL | Description |
|---------|-----|-------------|
| GET | `/api/setup/health` | État du serveur + `setup_done` |
| POST | `/api/setup/test-db` | Test credentials DB → écrit `pos_server.ini` |
| POST | `/api/setup/create-db` | Crée la base + tables |
| POST | `/api/setup/connect-tenant` | Lie l'installation à un compte tenant cloud |
| GET | `/api/public/identity?nonce=` | Signature Ed25519 du serveur (vérification identité) |
| POST | `/api/auth/login` | JWT token |
| GET/POST | `/api/products/` | CRUD produits |
| GET/POST | `/api/sales/` | CRUD ventes |
| GET/POST | `/api/purchases/` | CRUD achats |
| GET/POST | `/api/customers/` | CRUD clients |
| GET/POST | `/api/debts/` | Dettes clients/fournisseurs |
| GET | `/api/stock/` | Mouvements de stock |
| GET | `/api/billing/license` | Blob de licence signé Ed25519 (cache offline 7j) |
| GET | `/api/billing/caisse-count` | Caisses actives vs plan |
| POST | `/api/sync/token` | Échange credentials → sync token (365j) |
| POST | `/api/admin/tenants` | Créer un tenant (shared ou selfhosted) |
| PATCH | `/api/admin/tenants/{id}` | Modifier statut, type, max_caisses |

---

## Configuration

### pos_server.ini (généré automatiquement)

```ini
[database]
type     = mysql
host     = localhost
port     = 3306
name     = pos_db
user     = root
password = votre_mot_de_passe

[server]
host                 = 0.0.0.0
port                 = 8002
secret_key           = <généré automatiquement>
token_expire_minutes = 480
# Rempli par le wizard lors de la connexion tenant
cloud_sync_url       = https://self-hosted-ou-cloud.example.com
cloud_sync_token     = <sync JWT 365j>
cloud_sync_enabled   = true
billing_url          = https://posconnect.ht   # toujours posconnect.ht
# Sur posconnect.ht uniquement — identité Ed25519
identity_private_key =
```

### Créer un admin manuellement (sans wizard)

```bash
python seed_user.py
# Crée : username=admin / password=Admin@1234
```

---

## Build et distribution

Les binaires sont construits automatiquement via GitHub Actions sur chaque push :

| Plateforme | Artefact |
|------------|----------|
| Linux | `pos_connect-linux.tar.gz` |
| Windows | `pos_connect-windows.zip` |
| macOS | `pos_connect-macos.zip` |
| Android | `pos_connect-android.apk` |

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
```
