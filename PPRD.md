# PPRD — Product & Project Requirements Document
# POS Connect — Système de Caisse Multi-Plateforme

**Date :** 2026-06-14
**Version :** 0.5 (en développement actif)
**Stack backend :** Python 3.11 · FastAPI · SQLAlchemy · MySQL / SQLite · JWT
**Stack frontend :** Flutter 3.x · Riverpod · go_router · Dio · SharedPreferences

---

## 1. Vue d'ensemble du projet

Système de point de vente (POS) complet avec :
- **Backend API** (FastAPI) : REST, JWT, MySQL ou SQLite configurable
- **Frontend Flutter** (POS Connect) : application multi-plateforme (Linux, Windows, macOS, Android, Web/Chrome)
- **Wizard d'installation** : assistant guidé de configuration serveur/client intégré dans l'app Flutter

---

## 2. Architecture

### 2.1 Backend (pos_api)

| Composant | Technologie |
|-----------|-------------|
| Framework | FastAPI 0.127 |
| ORM | SQLAlchemy 2.0 |
| Base de données | MySQL (PyMySQL) ou SQLite |
| Migrations | Alembic 1.17 |
| Auth | JWT (PyJWT / python-jose) |
| Validation | Pydantic v2 |
| Serveur | Uvicorn |
| Config | `pos_server.ini` (priorité) + `.env` (fallback) |

### 2.2 Frontend (pos_connect / Flutter)

| Composant | Technologie |
|-----------|-------------|
| Framework | Flutter 3.x |
| État | Riverpod (StateProvider, ConsumerWidget) |
| Navigation | go_router |
| HTTP | Dio (singleton, baseUrl dynamique) |
| Persistance URL | SharedPreferences |
| Plateformes | Linux · Windows · macOS · Android · Web |

### 2.3 Configuration serveur

Le backend lit sa configuration dans cet ordre de priorité :
1. `pos_server.ini` (généré automatiquement par le wizard)
2. Variables d'environnement / `.env`
3. Valeurs par défaut (MySQL localhost)

---

## 3. Fonctionnalités implémentées

### 3.1 Wizard d'installation (InstallerScreen)

- [x] Étape 1 — Bienvenue
- [x] Étape 2 — Choix du mode : Serveur / Client / Les deux
- [x] Étape 3 — Adresse serveur
  - Client : saisie manuelle de l'URL serveur + test connexion
  - Serveur/Both : détection automatique des IPs locales via `NetworkInterface.list()`
  - Test connexion obligatoire avant de continuer
  - URL mise à jour en mémoire (`dio.options.baseUrl`) pendant le wizard, SharedPreferences écrit uniquement à la fin
  - Wizard repart toujours du défaut compilé (`AppConstants.baseUrl`) — ignore les SharedPreferences stale
- [x] Étape 4 — Choix base de données (MySQL ou SQLite)
- [x] Étape 5 — Configuration MySQL
  - Détection automatique auth_socket (Debian/Ubuntu)
  - Bouton "Corriger automatiquement (sudo)" via `Process.start('sudo', ['-S', 'mysql', ...])`
  - `pos_server.ini` écrit dès que le test de connexion réussit
- [x] Étape 6 — Compte administrateur
- [x] Étape 7 — Installation (create-db + init + service_wrapper)
  - Moteur temporaire SQLAlchemy bâti sur les credentials de la requête (indépendant du moteur global démarré au lancement)
  - `pos_server.ini` finalisé avec `secret_key` aléatoire
  - SharedPreferences mis à jour avec l'URL confirmée
- [x] Étape 8 — Terminé → bouton "Lancer POS Connect" navigue vers `/login`
- [x] Web : wizard jamais affiché (`kIsWeb` guard dans splash)

### 3.2 Authentification
- [x] Login username/password → JWT Bearer token
- [x] Middleware `get_current_user` via OAuth2PasswordBearer
- [x] Roles et permissions JSON dans le modèle User
- [x] Changement de mot de passe forcé (`must_change_password`)

### 3.3 Catalogue
- [x] CRUD Catégories
- [x] CRUD Produits (barcode, prix achat/vente, seuil alerte, images)
- [x] CRUD Fournisseurs
- [x] Recherche produits avec pagination (caisse)
- [x] Images produits servies via l'API, URL dynamique (`dio.options.baseUrl`)

### 3.4 Ventes
- [x] Création vente avec lignes (SaleItem)
- [x] Vérification stock avant vente
- [x] Mouvements stock OUT automatiques
- [x] Enregistrement paiement (CASH / BANK / MOBILE)
- [x] Création dette automatique si paiement partiel
- [x] Statuts : UNPAID / PAID / PARTIAL
- [x] Annulation de vente
- [x] Retour client

### 3.5 Achats fournisseurs
- [x] Création commande achat avec lignes
- [x] Paiement partiel/total
- [x] Réception partielle ou totale (PurchaseReceipt)
- [x] Mouvements stock IN à la réception
- [x] Retour fournisseur

### 3.6 Stock
- [x] Stock calculé via somme des StockMovement (pas de champ direct)
- [x] Types : in / out / adjust
- [x] Historique des mouvements avec filtres et pagination

### 3.7 Paiements et Dettes
- [x] Modèle Payment polymorphique (SALE ou PURCHASE)
- [x] Modèle Debt avec partner (CUSTOMER ou SUPPLIER)

### 3.8 Infrastructure backend
- [x] UUIDs pour toutes les entités
- [x] Timestamps automatiques sur toutes les tables
- [x] Pagination générique
- [x] `pos_server.ini` auto-généré par le wizard (plus besoin de copie manuelle)
- [x] `_is_setup_done` basé sur `COUNT(*) > 0` (compatible MySQL JSON column)
- [x] Endpoint `/setup/health` → `setup_done` bool
- [x] Endpoint `/setup/test-db` → écrit `pos_server.ini` si succès
- [x] Endpoint `/setup/create-db` → moteur temporaire, indépendant du global
- [x] Endpoint `/setup/init` → moteur temporaire, crée admin dans la bonne base

### 3.9 Multi-plateforme
- [x] Linux (desktop natif) — build GitHub Actions
- [x] Windows (desktop natif) — build GitHub Actions
- [x] macOS (desktop natif) — build GitHub Actions
- [x] Android (APK) — build GitHub Actions
- [x] Web/Chrome — compatible (`kIsWeb` guards sur `dart:io`)

### 3.10 Architecture SaaS multi-tenant

- [x] Modèle `Tenant` : slug, business_name, owner_email, status, is_local
- [x] `tenant_id` (UUID FK) sur toutes les tables métier
- [x] `TenantService` — base class injectant automatiquement le `tenant_id` dans tous les CRUD
- [x] Middleware `get_current_tenant()` : vérifie statut + gère la période de grâce
- [x] Tenant `__local__` créé au démarrage pour les déploiements hors SaaS (champ `is_local=True`)
- [x] Backfill automatique `tenant_id = NULL → __local__` sur toutes les tables au démarrage

### 3.11 Panel d'administration SaaS (`/admin`)

- [x] Authentification email + mot de passe (argon2id, via `pwdlib`)
  - Hash stocké dans `pos_server.ini` (`admin_password_hash`) ou `.env`
  - JWT superadmin : `{"sub": "superadmin", "role": "superadmin"}` — expiry 24h
- [x] Liste et gestion des tenants (statut, dates, plan)
- [x] Modification du statut tenant : `trial`, `active`, `expired`, `suspended`
- [x] Config plateforme (`PlatformConfig`) :
  - Numéros MonCash et NatCash
  - Prix des plans (mensuel, annuel)
  - Durée de l'essai gratuit (`trial_days`, configurable)
  - Mode paiement par service : `manual` ou `api_auto`
    - **Manuel** : le client paie le numéro affiché et saisit sa référence
    - **API auto** : paiement déclenché via l'API MonCash/NatCash (à venir)

### 3.12 Facturation et abonnements

- [x] Endpoint `GET /api/billing/status` : jours restants, statut, `is_grace`, `grace_days_left`
- [x] Endpoint `GET /api/billing/config` : numéros, prix, modes MonCash/NatCash (accès tenants)
- [x] Calcul précis des jours restants : `math.ceil(delta.total_seconds() / 86400)` (évite d'afficher 29j au lieu de 30j)
- [x] Cycle de vie abonnement :
  1. **trial** — essai gratuit (durée = `platform_config.trial_days`)
  2. **expired** — essai/plan expiré, grâce de 10 jours (`GRACE_DAYS = 10`), app fonctionne encore
  3. **suspended** — grâce expirée, accès bloqué (HTTP 403)
  4. **active** — abonnement payant en cours
- [x] Bandeau orange "période de grâce" dans l'écran de facturation Flutter
- [x] Écran facturation utilise les vraies données de `billing/config` (numéros, prix)
- [x] Statut "Expiré" affiché dans le panel admin avec couleur `deepOrange`

### 3.13 Synchronisation local ↔ cloud

#### Serveur cloud (multi-tenant)
- [x] `POST /api/sync/token` — tenant email+password → JWT sync (rôle `sync`, expiry 365j)
- [x] `POST /api/sync/push` — upsert de records dans la DB cloud (tenant_id injecté du token)
- [x] `GET /api/sync/pull?entity_type=&since=` — retourne records modifiés depuis `since`
- [x] `GET /api/sync/status` — état de la configuration et statistiques par entité
- [x] `POST /api/sync/run` — déclenche un cycle de synchronisation complet
- [x] `POST /api/sync/configure` — appelle `/api/sync/token` sur le cloud, sauvegarde dans `pos_server.ini`

#### Serveur local (`local_sync_service.py`)
- [x] Entités **bidirectionnelles** (catalog) : `category`, `supplier`, `product`, `customer`
- [x] Entités **push only** (transactions) : `sale`, `sale_item`, `payment`, `purchase`, `purchase_item`, `return_record`
- [x] Résolution de conflits : **last-write-wins** sur `updated_at`
- [x] Table `SyncState` : `entity_type`, `last_push_at`, `last_pull_at`, `records_pushed`, `records_pulled`, `last_error`
- [x] Sécurité push : `tenant_id` exclu de la payload — assigné côté cloud via JWT

#### UI Flutter (Settings)
- [x] Section "Synchronisation Cloud" visible à tous les admins
- [x] Formulaire de configuration (URL cloud, email, mot de passe)
- [x] Tableau des statistiques par entité (push/pull, horodatage, erreurs)
- [x] Bouton "Synchroniser maintenant" avec résultat affiché (`Envoyé: X | Reçu: Y`)
- [x] Statut de connexion (configuré / non configuré)

---

## 4. Bugs connus et points d'attention

### 4.1 Backend

| # | Statut | Problème |
|---|--------|----------|
| B1 | Résolu | `_is_setup_done` utilisait un filtre JSON incompatible MySQL → remplacé par `count()` |
| B2 | Résolu | `create-db` / `init` utilisaient le moteur global (mauvais credentials au 1er démarrage) |
| B3 | Résolu | `pos_server.ini` écrit trop tard (fin du wizard) → maintenant écrit dès le test DB |
| B4 | Actif | `pos_server.ini` non rechargé en cours d'exécution → redémarrage serveur requis après wizard |
| B5 | Résolu | Admin auth : `Auth.verify_password()` appelé comme méthode statique → utilise `pwdlib` directement |
| B6 | Résolu | Jours d'essai affichés : `timedelta.days` (floor) → `math.ceil(delta.total_seconds() / 86400)` |
| B7 | Résolu | `trial_ends_at` non mis à jour en base au bon nombre de jours → commit explicite requis |
| B8 | Résolu | `No module named 'requests'` dans `local_sync_service` → remplacé par `httpx` |

### 4.2 Frontend

| # | Statut | Problème |
|---|--------|----------|
| F1 | Résolu | URL serveur sauvegardée dans SharedPreferences à chaque test → maintenant uniquement à la fin |
| F2 | Résolu | Wizard lisait SharedPreferences stale → maintenant reset à `AppConstants.baseUrl` à l'ouverture |
| F3 | Résolu | Images produits URL hardcodée (compile-time) → maintenant `dio.options.baseUrl` (runtime) |
| F4 | Résolu | `Platform._operatingSystem` crash sur web → guards `!kIsWeb` |
| F5 | Résolu | Bouton "Lancer POS Connect" inactif → navigate vers `/login` |
| F6 | Actif | Serveur non redémarré automatiquement après wizard sur desktop (service_wrapper optionnel) |
| F7 | Résolu | Panel admin "Erreur de chargement" sur Paramètres → colonnes `moncash_mode`/`natcash_mode` manquantes en DB |
| F8 | Résolu | Données admin non rafraîchies après save → `_loaded = false` manquant avant `ref.invalidate()` |
| F9 | Résolu | Section sync invisible → condition `tenant == null` excluait les cloud users → condition supprimée |

---

## 5. Déploiement

### 5.1 Serveur (Debian/Ubuntu recommandé)

```bash
cd ~/posconnect
./pos_api          # Lance le backend FastAPI sur le port 8002
./pos_connect      # Lance le wizard + client Flutter
```

Le wizard crée automatiquement `pos_server.ini` et la base de données.

### 5.2 Client (autre machine)

1. Copier `pos_connect` sur la machine cliente
2. Lancer l'app → wizard → Mode "Client uniquement"
3. Entrer l'URL du serveur (ex: `http://192.168.0.110:8002`)
4. Tester la connexion → login

### 5.3 Web (Chrome)

L'app Flutter fonctionne dans un navigateur. L'URL serveur est le défaut compilé (`AppConstants.baseUrl`). Le wizard d'installation n'est pas disponible sur web.

### 5.4 Build CI/CD

GitHub Actions construit automatiquement sur chaque push vers `main` :
- `pos_connect-linux.tar.gz`
- `pos_connect-windows.zip`
- `pos_connect-macos.zip`
- `pos_connect-android.apk`

---

## 6. Configuration

### pos_server.ini (généré automatiquement par le wizard)

```ini
[database]
type     = mysql          # mysql | sqlite
host     = localhost
port     = 3306
name     = pos_db
user     = root
password = votre_mot_de_passe
path     = ./pos_data.db  # utilisé uniquement si type=sqlite

[server]
host                  = 0.0.0.0
port                  = 8002
secret_key            = <généré automatiquement>
token_expire_minutes  = 480
# Compte super-admin pour le panel /admin
# Hash généré avec : python -c "from pwdlib import PasswordHash; print(PasswordHash.recommended().hash('MonMotDePasse'))"
admin_email           = admin@posconnect.ht
admin_password_hash   = $argon2id$v=19$...

# Synchronisation local ↔ cloud (rempli par POST /api/sync/configure)
cloud_sync_url        =
cloud_sync_token      =
cloud_sync_enabled    = false
```

### .env (fallback développement)

```env
DB_TYPE=mysql
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=votre_mot_de_passe
DB_NAME=pos_db
SECRET_KEY=change_me_use_openssl_rand_hex_32
```

---

## 7. Schéma de base de données

```
tenants         ← gestionnaire d'accès SaaS (status, trial_ends_at, plan)
  │
  ├── users           categories      suppliers
  │     │                │               │
  │     │           products ────────────┘
  │     │               │
  │     ├── sales ──────┤
  │     │     └── sale_items
  │     │     └── payments (reference_type=SALE)
  │     │     └── debts   (reference_type=SALE)
  │     │
  │     └── purchases ──┤
  │           └── purchase_items
  │                 └── purchase_receipt_items
  │           └── purchase_receipts
  │           └── payments (reference_type=PURCHASE)
  │           └── debts   (reference_type=PURCHASE)
  │
  └── (toutes les tables ci-dessus ont tenant_id UUID FK)

stock_movements   ← lié à Product + User + source (sale/purchase/adjust)
app_config        ← paramètres persistants (multi-device sync)
platform_config   ← config SaaS globale (numéros, prix, modes, trial_days)
billing_payments  ← historique paiements abonnements
sync_state        ← état de synchro par entity_type (last_push_at, last_pull_at, counts)
roles             ← rôles personnalisés par tenant
```

---

## 8. Prochaines étapes

| Priorité | Feature |
|----------|---------|
| Haute | Rechargement automatique de `pos_server.ini` sans redémarrage |
| Haute | Page de configuration URL serveur sur web (remplace le wizard) |
| Haute | Service système automatique (systemd) pour démarrage au boot |
| Haute | Synchronisation automatique périodique (cron / background task) |
| Haute | Intégration API MonCash pour paiements automatiques (mode `api_auto`) |
| Haute | Intégration API NatCash pour paiements automatiques (mode `api_auto`) |
| Moyenne | Dashboard statistiques complet |
| Moyenne | Impression tickets (intégration `printing`) |
| Moyenne | Portail self-service tenant (upgrade plan, historique factures) |
| Basse | Migration de données SQLite → MySQL |
| Basse | Tests unitaires backend (pytest) |
| Basse | Webhook callbacks après paiement MonCash/NatCash |
