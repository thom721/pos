# PPRD — Product & Project Requirements Document
# POS Connect — Système de Caisse Multi-Plateforme

**Date :** 2026-06-16
**Version :** 0.6 (en développement actif)
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
- [x] Étape 6 — Compte cloud (connexion tenant)
  - Remplace la création d'un compte admin local
  - Saisie : URL cloud, email tenant, mot de passe
  - Vérification d'identité Ed25519 du serveur (nonce signé) avant envoi des credentials
  - Connexion à `/api/sync/token` → récupère `tenant_type`, `self_hosted_url`, `max_caisses`
  - Si `selfhosted` : `cloud_sync_url` pointe vers `self_hosted_url`, `billing_url` vers posconnect.ht
  - Si `shared` : `cloud_sync_url` et `billing_url` pointent tous deux vers posconnect.ht
- [x] Étape 7 — Installation (create-db + connect-tenant + service_wrapper)
  - Moteur temporaire SQLAlchemy bâti sur les credentials de la requête
  - `pos_server.ini` finalisé avec `secret_key` aléatoire, `billing_url`, `cloud_sync_token`
  - SharedPreferences mis à jour avec l'URL confirmée
- [x] Étape 8 — Terminé → affiche email tenant + "Synchronisation active"
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
  - Premier démarrage cloud : auto-génération email/password → stocké dans `PlatformConfig` (DB), journal serveur
  - JWT superadmin : `{"sub": "superadmin", "role": "superadmin"}` — expiry 24h
- [x] `POST /api/admin/tenants` — créer un tenant avec :
  - `type` : `shared` (données sur posconnect.ht) ou `selfhosted` (données sur le propre serveur du tenant)
  - `self_hosted_url` : URL du serveur self-hosted (obligatoire si `selfhosted`)
  - `max_caisses` : nombre de caisses inclus dans le plan
  - `can_manage_tenants` : autoriser le tenant self-hosted à gérer ses propres sous-tenants
- [x] Liste et gestion des tenants (statut, type, max_caisses, can_manage_tenants)
- [x] `PATCH /api/admin/tenants/{id}` — modifier statut, type, self_hosted_url, max_caisses, can_manage_tenants
- [x] Config plateforme (`PlatformConfig`) :
  - Numéros MonCash et NatCash
  - Prix des plans (mensuel, annuel)
  - Durée de l'essai gratuit (`trial_days`, configurable)
  - Prix par caisse supplémentaire : `price_per_extra_caisse_htg` / `price_per_extra_caisse_usd`
  - Mode paiement par service : `manual` ou `api_auto`
    - **Manuel** : le client paie le numéro affiché et saisit sa référence
    - **API auto** : paiement déclenché via l'API MonCash/NatCash (à venir)

### 3.12 Facturation et abonnements

- [x] Endpoint `GET /api/billing/status` : jours restants, statut, `is_grace`, `grace_days_left`
- [x] Endpoint `GET /api/billing/config` : numéros, prix, modes MonCash/NatCash, prix par caisse extra
- [x] Endpoint `GET /api/billing/caisse-count` : caisses actives vs max_caisses, montant facturation extra
- [x] Endpoint `GET /api/billing/license` : blob JSON signé Ed25519 (valide 7 jours) incluant :
  - `tenant_type`, `self_hosted_url`, `max_caisses`, `current_caisses`
  - `status`, `valid_until`, `trial_ends_at`, `subscription_ends_at`
  - Prix par caisse supplémentaire
  - **Proxy transparent** : si `BILLING_URL` est configuré (serveur self-hosted / local), proxyfie vers `GET /api/billing/license-sync-proxy` sur posconnect.ht avec le sync token
- [x] Endpoint `GET /api/billing/license-sync-proxy` : accepte un sync token (Bearer) — cible du proxy self-hosted
- [x] Calcul précis des jours restants (`math.ceil`)
- [x] Cycle de vie abonnement :
  1. **trial** — essai gratuit (durée = `platform_config.trial_days`)
  2. **expired** — essai/plan expiré, grâce de 10 jours (`GRACE_DAYS = 10`), app fonctionne encore
  3. **suspended** — grâce expirée, accès bloqué (HTTP 403)
  4. **active** — abonnement payant en cours
- [x] Bandeau orange "période de grâce" dans l'écran de facturation Flutter
- [x] Écran facturation utilise les vraies données de `billing/config`
- [x] Statut "Expiré" affiché dans le panel admin avec couleur `deepOrange`

### 3.13 Synchronisation local ↔ cloud

#### Serveur cloud (multi-tenant)
- [x] `POST /api/sync/token` — tenant email+password → JWT sync (rôle `sync`, expiry 365j)
  - Retourne : `sync_token`, `tenant_type`, `self_hosted_url`, `max_caisses`, `can_manage_tenants`
- [x] `POST /api/sync/push` — upsert de records dans la DB cloud
  - **Bloqué pour les tenants `selfhosted`** : leurs données business ne sont pas stockées sur posconnect.ht
- [x] `GET /api/sync/pull?entity_type=&since=` — retourne records modifiés depuis `since`
  - **Bloqué pour les tenants `selfhosted`** : récupérer depuis `self_hosted_url`
- [x] `GET /api/sync/status` — état de la configuration et statistiques par entité
- [x] `POST /api/sync/run` — déclenche un cycle de synchronisation complet
- [x] `POST /api/sync/configure` — appelle `/api/sync/token` sur le cloud, sauvegarde dans `pos_server.ini`

#### Tenant `shared` — comportement inchangé
- Toutes les données business synchronisées vers posconnect.ht

#### Tenant `selfhosted` — sync minimal
- Données business → leur propre serveur (`self_hosted_url`)
- Seuls billing / statut / plan → posconnect.ht
- Serveur local (client-server) : `cloud_sync_url` = `self_hosted_url` dans `pos_server.ini`

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

### 3.14 Identité serveur Ed25519

- [x] Clé privée Ed25519 (`IDENTITY_PRIVATE_KEY`) stockée dans `pos_server.ini` ou `.env` — lecture via `settings`
- [x] Clé publique correspondante hardcodée dans le binaire Flutter (`AppConstants.identityPublicKeyB64`)
- [x] `GET /api/public/identity?nonce=` — signe `{app}:{nonce}` avec la clé privée → retourne signature base64
- [x] Wizard Flutter : avant connexion tenant, vérifie l'identité du serveur (nonce aléatoire → vérification Ed25519)
  - Empêche la connexion à un serveur imposteur
  - Nonce hex 24 chars généré avec `Random.secure()`

### 3.15 Cache de licence offline

- [x] `GET /api/billing/license` retourne un blob JSON signé Ed25519 (valide 7 jours)
- [x] `LicenseService` (Flutter) :
  - Essaie d'abord le serveur (frais), sinon lit le cache `FlutterSecureStorage`
  - Vérifie la signature avec la clé publique hardcodée (posconnect.ht)
  - `clearCache()` appelé au logout
- [x] `licenseProvider` (Riverpod `FutureProvider`) — se reconstruit à chaque login/logout
- [x] `AppShell` — selon `LicenseStatus.access` :
  - `allowed` : shell normal (éventuellement bannière info)
  - `warning` : bannière jaune (offline) ou rouge (expiré en grâce) + shell
  - `blocked` : écran de blocage complet (suspendu ou grâce dépassée)
- [x] Grâce offline : 7 jours `valid_until` + 3 jours = 10 jours max sans internet

### 3.16 Mode self-hosted

- [x] Tenant `type = 'selfhosted'` : données business hébergées sur le propre serveur du tenant
- [x] `self_hosted_url` : URL du serveur du tenant, synchronisée via `/api/sync/token`
- [x] `max_caisses` : nombre de postes caisse (rôle `cashier`) inclus dans le plan
  - Comptage : `COUNT(users WHERE 'cashier' IN roles)`
  - Dépassement facturé au prix `price_per_extra_caisse_htg/usd` configuré dans `PlatformConfig`
- [x] `can_manage_tenants` : autorise un tenant self-hosted à gérer ses propres clients (champ admin)
- [x] `AppShell` bannière orange si `caisseOverLimit` — affiche coût des caisses en excès
- [x] Proxy billing transparent : le serveur self-hosted / local proxyfie `GET /api/billing/license` vers posconnect.ht — aucun changement côté Flutter

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

# Compte super-admin pour le panel /admin (auto-généré au 1er démarrage cloud)
admin_email           = admin@posconnect.ht
admin_password_hash   = $argon2id$v=19$...

# Synchronisation données business
# shared  : cloud_sync_url = posconnect.ht
# selfhosted : cloud_sync_url = self_hosted_url du tenant
cloud_sync_url        =
cloud_sync_token      =
cloud_sync_enabled    = false

# URL du serveur de billing (toujours posconnect.ht, séparé de cloud_sync_url)
# Rempli par le wizard lors de la connexion tenant
billing_url           =

# Identité serveur Ed25519 (base64 raw 32 bytes) — UNIQUEMENT sur posconnect.ht
identity_private_key  =
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
tenants         ← gestionnaire d'accès SaaS
  │  status, trial_ends_at, plan
  │  type ('shared'|'selfhosted'), self_hosted_url
  │  max_caisses, can_manage_tenants
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
platform_config   ← config SaaS globale (numéros, prix, modes, trial_days,
                     admin_email, admin_password_hash,
                     price_per_extra_caisse_htg/usd)
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
| Haute | Portail self-service tenant (upgrade plan, changer self_hosted_url, voir caisses) |
| Haute | Wizard configuration self-hosted server (BILLING_URL + CLOUD_SYNC_TOKEN via Docker env) |
| Moyenne | Dashboard statistiques complet |
| Moyenne | Impression tickets (intégration `printing`) |
| Moyenne | Facture récapitulative mensuelle par tenant (extra caisses + plan) |
| Basse | Migration de données SQLite → MySQL |
| Basse | Tests unitaires backend (pytest) |
| Basse | Webhook callbacks après paiement MonCash/NatCash |
