# POS Connect — Système de Caisse Multi-Plateforme

Système de point de vente complet : **backend FastAPI** + **frontend Flutter** multi-plateforme.

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
- Création du compte administrateur
- Génération automatique de `pos_server.ini`

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
| POST | `/api/setup/init` | Crée le compte admin |
| POST | `/api/auth/login` | JWT token |
| GET/POST | `/api/products/` | CRUD produits |
| GET/POST | `/api/sales/` | CRUD ventes |
| GET/POST | `/api/purchases/` | CRUD achats |
| GET/POST | `/api/customers/` | CRUD clients |
| GET/POST | `/api/debts/` | Dettes clients/fournisseurs |
| GET | `/api/stock/` | Mouvements de stock |

---

## Configuration

### pos_server.ini (généré automatiquement)

```ini
[database]
type     = mysql          # mysql | sqlite
host     = localhost
port     = 3306
name     = pos_db
user     = root
password = votre_mot_de_passe

[server]
host                 = 0.0.0.0
port                 = 8002
secret_key           = <généré automatiquement 32 bytes>
token_expire_minutes = 480
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
