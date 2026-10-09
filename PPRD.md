# PPRD — Product & Project Requirements Document
# POS Connect — Système de Caisse Multi-Plateforme

**Date :** 2026-10-09
**Version :** 0.9 (en développement actif) — app 2.0.0+57, tag v2.0.63
**Stack backend :** Python 3.11 · FastAPI · SQLAlchemy · MySQL / SQLite · JWT
**Stack frontend :** Flutter 3.x · Riverpod · go_router · Dio · SharedPreferences

---

## 1. Vue d'ensemble du projet

Système de point de vente (POS) complet avec :
- **Backend API** (FastAPI) : REST, JWT, MySQL ou SQLite configurable
- **Frontend Flutter** (POS Connect) : application multi-plateforme (Linux, Windows, macOS, Android, Web/Chrome)
- **Wizard d'installation** : assistant guidé de configuration serveur/client intégré dans l'app Flutter
- **Mode restaurant** : tables, serveurs, commandes cuisine, encaissement avec pourboire
- **Architecture SaaS multi-tenant** : shared / self-hosted, billing, synchronisation cloud

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
| Stockage sécurisé | FlutterSecureStorage (JWT, licence) |
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
  - Saisie : URL cloud, email tenant, mot de passe
  - Vérification d'identité Ed25519 du serveur (nonce signé) avant envoi des credentials
  - Connexion à `/api/sync/token` → récupère `tenant_type`, `self_hosted_url`, `max_caisses`
- [x] Étape 7 — Installation (create-db + connect-tenant + service_wrapper)
- [x] Étape 8 — Terminé → affiche email tenant + "Synchronisation active"
- [x] Web : wizard jamais affiché (`kIsWeb` guard dans splash)

### 3.2 Authentification et accès

- [x] Login username/password → JWT Bearer token
- [x] Middleware `get_current_user` via OAuth2PasswordBearer
- [x] Roles et permissions JSON dans le modèle User
- [x] Changement de mot de passe forcé (`must_change_password`)
- [x] Splash screen : fast-path `/dashboard` si JWT valide en `FlutterSecureStorage` (évite animation répétée)
- [x] Matrice de permissions complète par rôle :
  - `admin` : toutes permissions
  - `manager` : gestion complète hors admin système
  - `cashier` : ventes, retours, lecture stock/produits/clients, tables restaurant
- [x] Messages d'erreur localisés pour 401/403/503 (`extractAnyError`)

### 3.3 Catalogue

- [x] CRUD Catégories
- [x] CRUD Produits (barcode, prix achat/vente, seuil alerte, images)
- [x] `warehouse_id` optionnel sur les produits — backend (FK + index), schemas Pydantic, migration `h8i9j0k1l2m3`
- [x] Flutter : champ `warehouseId` dans `ProductModel` (fromJson/toJson) + sélecteur dépôt dans le formulaire produit (affiché uniquement si le tenant a plusieurs dépôts)
- [x] SQLite v13 : colonne `warehouse_id` ajoutée à la table `products` locale (upsert + lecture)
- [x] CRUD Fournisseurs
- [x] Recherche produits avec pagination (caisse)
- [x] Images produits servies via l'API, URL dynamique (`dio.options.baseUrl`)
- [x] Pagination navigable sur l'écran Produits (précédent/suivant, retour auto si page vide)
- [x] Multi-devise d'affichage/saisie ($HT/USD/EUR) — HTG reste l'unique source de vérité en base, conversion à l'affichage et à la saisie (`core/currency.dart`)
- [x] Suppression sécurisée d'un produit : verrouillage (réversible) si historique bloquant, sinon suppression totale
- [x] Produits composés : reste d'unités du composant affiché (ex: "3 (+8)") au lieu d'une fraction décimale trompeuse
- [x] `warehouse_id` obligatoire sur un produit (plus d'option "Tous les dépôts" au formulaire) — le stock est suivi par (produit, dépôt), un produit partagé affichait un stock à 0 au changement de dépôt
- [x] Changement de dépôt d'un produit : bloqué s'il a déjà des ventes enregistrées (historique rattaché à ce dépôt), sinon le stock existant est migré automatiquement vers le nouveau dépôt (notification de la quantité transférée)
- [x] Produit verrouillé (`is_locked`) : toute modification bloquée sauf le déverrouillage lui-même
- [x] Dépôt actif pré-sélectionné à la création d'un produit (au lieu de "Tous les dépôts" par défaut)
- [x] **Type de produit "Service"** (`products.is_service`, défaut `false`) — pour les commerces proposant des services (pressing, lessive...) sans stock/quantité suivie
  - Backend : stock/quantité disponible jamais vérifiés à la vente, aucun `StockMovement` créé (création, modification, annulation, retour)
  - Onglet "Produit" / "Service" sur les écrans Produits et Ventes (`item_type=product|service`) — "Produit" par défaut ; une vente mixte (contient les deux) apparaît dans les deux onglets côté Ventes
  - Formulaire produit : switch "Service" en tout premier champ, pilote le titre du dialogue ("Nouveau service"/"Nouveau produit"), masque Seuil d'alerte/Produit composé/Paliers de prix, relabel "Prix achat"/"Prix vente" → "Coût"/"Prix"
  - Exclu des alertes stock bas, du digest email quotidien et du comptage d'inventaire
  - Historique des mouvements et "Retourner à l'entrepôt" désactivés (tooltip explicatif) dans la liste produits
  - Référence de vente dédiée `SER-00001` (compteur indépendant de `VNT-`, scopé par dépôt) pour une vente composée uniquement de services ; une vente mixte garde `VNT-`
  - Section "Services" séparée dans le PDF du rapport de ventes (liste par article, triée par numéro de référence croissant)
  - Support complet Android hors-ligne (cache SQLite : colonne `is_service`, migration locale v31, jointure `sale_items`→`products`)
- [x] **Paliers de prix (gros)** (`product_price_tiers` : `product_id`, `warehouse_id`, `min_quantity`, `price`) — prix dégressif par dépôt à partir d'une quantité
  - Le palier le plus élevé atteint par la quantité de la ligne s'applique ; le serveur fait foi même si le client envoie un `unit_price` différent
  - Édition dans la fiche produit ("Paliers de prix (gros)", visible en modification, par dépôt du produit) ; consultation en lecture seule dans la fiche détails (clic sur une ligne du tableau Produits)
  - Caisse : `priceTiersProvider` charge tous les paliers du dépôt actif en un seul appel (`GET /api/price-tiers`), `CartItem.tierPrice` applique le palier atteint selon la quantité en temps réel
  - Libellé reçu : "Rabais" (écart prix catalogue / prix facturé, inclut les paliers)

### 3.4 Ventes

- [x] Création vente avec lignes (SaleItem)
- [x] Vérification stock avant vente
- [x] Mouvements stock OUT automatiques
- [x] Enregistrement paiement (CASH / BANK / MOBILE)
- [x] Création dette automatique si paiement partiel
- [x] Statuts : UNPAID / PAID / PARTIAL
- [x] Annulation de vente
- [x] Retour client (permission `returns.create` accordée aux caissiers)
- [x] Filtre par période (date range) + pagination sur l'historique des ventes
- [x] Nom du caissier affiché sur chaque carte de vente
- [x] Numérotation séquentielle (`VNT-00001`) appliquée aussi à l'encaissement d'une commande restaurant (générait auparavant une référence aléatoire, non isolée par dépôt)
- [x] **Durcissement de l'autorisation par dépôt** (suite à un incident de production : vente d'un caissier comptabilisée sur le mauvais business) :
  - vente rejetée si le dépôt demandé n'appartient pas à la liste des dépôts autorisés du caissier
  - résolution du dépôt par priorité stricte : session de caisse ouverte (`CashierSession.warehouse_id`) > dépôt unique assigné au caissier > jamais un repli silencieux sur le dépôt par défaut du tenant
  - tenant multi-dépôts : vente rejetée (400) plutôt que devinée si le dépôt reste ambigu (aucune session, aucun dépôt explicite, plusieurs dépôts assignés)
  - même vérification ajoutée au login (`cloud_login`) et à l'ouverture de session de caisse (`open_session`) — un appareil déjà lié à la caisse d'un autre dépôt était sinon réutilisé tel quel

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

### 3.8 Mode Restaurant

#### Modèles

| Modèle | Table | Description |
|--------|-------|-------------|
| `RestaurantTable` | `restaurant_tables` | Table physique : nom, capacité, statut, serveur assigné |
| `RestaurantOrder` | `restaurant_orders` | Commande par table : couverts, notes, pourboire, statut |
| `RestaurantOrderItem` | `restaurant_order_items` | Ligne de commande : produit, quantité, statut cuisine |

#### Statuts

- **Table** : `free` · `occupied` · `reserved`
- **Commande** : `open` · `sent_to_kitchen` · `ready` · `closed`
- **Article** : `pending` · `preparing` · `ready`

#### API Restaurant (`/api/restaurant/`)

| Méthode | URL | Description |
|---------|-----|-------------|
| GET | `/waiters/` | Liste des utilisateurs actifs (pour assignation serveur) |
| GET | `/tables/` | Toutes les tables (manager) ou tables du serveur (caissier) |
| POST | `/tables/` | Créer une table |
| PUT | `/tables/{id}` | Modifier nom/capacité/statut |
| PUT | `/tables/{id}/assign` | Assigner un serveur à une table (manager) |
| DELETE | `/tables/{id}` | Supprimer une table |
| GET | `/orders/` | Commandes ouvertes |
| GET | `/orders/table/{table_id}` | Commande active d'une table |
| POST | `/orders/` | Ouvrir une commande (avec nombre de couverts) |
| POST | `/orders/{id}/items` | Ajouter un article |
| DELETE | `/orders/{id}/items/{item_id}` | Retirer un article |
| PUT | `/orders/{id}/kitchen` | Envoyer en cuisine |
| PUT | `/orders/{id}/ready` | Marquer comme prête |
| POST | `/orders/{id}/checkout` | Encaisser (crée Sale + Payment + libère table) |

#### Logique d'encaissement restaurant

1. Calcul : `total = subtotal - discount + tip`
2. Crée une `Sale` + `SaleItem`s + `Payment`
3. Si `paid < total` : crée une `Debt`
4. Met l'ordre à `closed`, la table à `free`
5. Retourne : `reference`, `subtotal`, `discount`, `tip`, `total`, `paid`, `change`, `covers`, `table_name`

#### UI Flutter

| Écran | Route | Description |
|-------|-------|-------------|
| Plan de salle | `/restaurant/tables` | Grille de tables colorées (vert/orange/bleu), long-press pour options |
| Commande table | `/restaurant/table/:tableId` | Recherche produit, liste articles, envoi cuisine, encaissement |
| Vue cuisine | `/restaurant/kitchen` | Toutes les commandes ouvertes, statut par article, "Marquer prêt" |

#### Fonctionnalités UI restaurant

- [x] Assignation serveur à une table (dialog avec liste radio)
- [x] Affichage du nom du serveur sur chaque carte de table
- [x] Picker de couverts à l'ouverture d'une commande
- [x] Champ pourboire dans le dialog d'encaissement (total recalculé en temps réel)
- [x] Reçu détaillé : table, couverts, sous-total, remise, pourboire, monnaie à rendre
- [x] Filtrage tables : admins / managers / caissiers voient **toutes les tables** ; seuls les utilisateurs avec rôle `serveur` sont filtrés à leurs propres tables
- [x] Plats (menu items) partagés à l'échelle du tenant — non filtrés par dépôt
- [x] Modal Nouveau/Modifier le plat : sélecteur de dépôt affiché uniquement si le tenant possède plusieurs dépôts
- [x] `menu_items.variants` (JSON) — variantes de prix par taille / option
- [x] `menu_items.send_to_kitchen` (bool, défaut `true`) — contrôle si l'article passe en vue cuisine
- [x] `restaurant_order_items.menu_item_id` — lien direct au plat (product_id maintenant nullable)
- [x] `modifier_groups` liés aux plats via `menu_item_id`
- [x] `sale_items.label` — conserve le nom du plat dans l'historique ventes
- [x] `restaurant_tables.price` — tarif (pour mode hôtel : prix de la chambre / nuit)
- [x] Navigation adaptative selon `business_type` (restaurant vs commerce) dans `AppShell`

### 3.9 Navigation adaptative par type de commerce

Le champ `business_type` de `AppConfig` / `AppSettings` pilote la navigation :

| `business_type` | Navigation principale | Bottom bar Android |
|---|---|---|
| `commerce` (défaut) | Caisse, Ventes, **Factures / Devis**, Produits, Clients, Dettes, Stock | Caisse, Ventes, Produits, Stock |
| `restaurant` | Tables, Cuisine, Ventes, **Factures / Devis**, Produits, Clients, Dettes | Tables, Cuisine, Ventes, Produits |
| `hotel` | Chambres, Transactions, **Factures / Devis**, Bar & Produits, Clients, Dettes | Chambres, Transactions, Produits |

Implémenté via `_resolveMainNav(businessType)` et `_resolveAndroidBottom(businessType)` dans `AppShell`.

### 3.10 Infrastructure backend

- [x] UUIDs pour toutes les entités
- [x] Timestamps automatiques sur toutes les tables
- [x] Pagination générique
- [x] `pos_server.ini` auto-généré par le wizard
- [x] Endpoint `/setup/health` → `setup_done` bool
- [x] `BackgroundTasks` FastAPI pour notifications WebSocket non bloquantes
- [x] `pool_pre_ping=True` + `pool_recycle=1800` sur le moteur SQLAlchemy (évite "MySQL gone away")

### 3.11 Architecture SaaS multi-tenant

- [x] Modèle `Tenant` : slug, business_name, owner_email, status, is_local
- [x] `tenant_id` (UUID FK) sur toutes les tables métier
- [x] `TenantService` — base class injectant automatiquement le `tenant_id` dans tous les CRUD
- [x] Middleware `get_current_tenant()` : vérifie statut + gère la période de grâce
- [x] Tenant `__local__` créé au démarrage pour les déploiements hors SaaS (`is_local=True`)

### 3.12 Panel d'administration SaaS (`/admin`)

- [x] Authentification email + mot de passe (argon2id, via `pwdlib`)
  - Hash stocké dans `PlatformConfig` (DB) — premier démarrage auto-génère credentials
  - JWT superadmin : `{"sub": "superadmin", "role": "superadmin"}` — expiry 24h
- [x] `POST /api/admin/tenants` — créer un tenant avec type (`shared`/`selfhosted`), `max_caisses`, `can_manage_tenants`
- [x] `PATCH /api/admin/tenants/{id}` — modifier statut, type, self_hosted_url, max_caisses
- [x] Config plateforme (`PlatformConfig`) : numéros MonCash/NatCash, prix plans, durée essai, prix par caisse supplémentaire, mode paiement (`manual`/`api_auto`)
- [x] `PlatformConfig.update_url` — lien téléchargement Windows/Desktop (GitHub Releases)
- [x] `PlatformConfig.update_url_android` — lien Google Play (facultatif, indépendant)
- [x] Bouton "Télécharger" dans le bandeau de mise à jour et l'écran force-update : ouvre l'URL via `url_launcher` (Android → Google Play, Desktop → GitHub, Web → texte "Rechargez la page")

### 3.13 Facturation et abonnements

- [x] `GET /api/billing/status` : jours restants, statut, `is_grace`, `grace_days_left`
- [x] `GET /api/billing/config` : numéros, prix, modes MonCash/NatCash
- [x] `GET /api/billing/caisse-count` : caisses actives vs max_caisses, montant facturation extra
- [x] `GET /api/billing/license` : blob JSON signé Ed25519 (valide 7 jours)
- [x] Cycle de vie : **trial** → **expired** (grâce 10j) → **suspended** → **active**
- [x] Bannière orange "période de grâce" dans l'écran facturation Flutter
- [x] Menu "Abonnement" visible pour admins sur web et desktop (via `kIsWeb` + rôle)

#### Trial par caisse (`PosRegister`)

- [x] Chaque `PosRegister` possède son propre `trial_ends_at` — indépendant du tenant et du dépôt
- [x] Les trois colonnes de dates (`trial_ends_at`, `subscription_started_at`, `subscription_ends_at`) sont chiffrées en Fernet (HKDF par caisse) et stockées en `TEXT(600)` dans MySQL
- [x] La propriété Python `trial_ends_at` est un `@property` avec getter/setter — chiffrement transparent
- [x] **Règle absolue** : `trial_ends_at = datetime.now(timezone.utc) + timedelta(days=trial_days)` dans tous les chemins de création :
  - `register_tenant()` dans `tenant_service.py` — inscription web
  - `create_warehouse()` dans `warehouse.py` — caisse initiale à la création d'un dépôt
  - `create_register()` dans `warehouse.py` — ajout manuel d'une caisse
- [x] Migration `f8bf3dfe3543` : correctif idempotent `MODIFY COLUMN TEXT(600)` pour les déploiements où `s5t6u7v8w9x0` a été estampillé sans avoir tourné

### 3.14 Synchronisation local ↔ cloud

- [x] `POST /api/sync/token` — credentials tenant → JWT sync (365j)
- [x] `POST /api/sync/push` / `GET /api/sync/pull` / `POST /api/sync/pull-batch` — upsert bidirectionnel
- [x] `POST /api/sync/run` — cycle complet
- [x] Table `SyncState` : watermarks par entity_type (réinitialisé automatiquement après l'ajout d'une colonne en local — voir B21)
- [x] ~40 entités synchronisées (`SYNC_ENTITIES`), la plupart bidirectionnelles ; push-only : `cashier_session`, `audit_log`, `restaurant_order(_item)`, `housekeeping_task` ; pull-only : `app_config`
- [x] Résolution conflits : last-write-wins sur `updated_at`
- [x] Bug timezone corrigé : `datetime.now()` (local) remplacé par `datetime.now(timezone.utc)` pour éviter les comparaisons incohérentes
- [x] **Synchronisation scopée par dépôt** — le serveur local envoie son `installer_warehouse_id` (en-tête `X-Warehouse-Id`), vérifié contre le tenant du token ; le cloud filtre pull/pull-batch/push sur ce dépôt pour les entités qui y sont propres (lignes enfants via leur entité parente) ; une installation ignore à la réception toute ligne d'un autre dépôt
  - Entités "nullable par dépôt" (`discount`, `app_config`) : ligne propre à un dépôt **ou** ligne globale (`NULL` = partagée par tous)
  - `user` (liste JSON de dépôts) et la ligne `app_config` globale restent au niveau du tenant, non filtrés par dépôt
  - Rabais par dépôt (`discounts.warehouse_id`) — une vente refuse un rabais qui n'appartient pas à son dépôt
- [x] **Synchronisation temps réel ciblée** (WebSocket) :
  - le serveur local écoute le push WebSocket du cloud (`{type: sync}`) et synchronise immédiatement, au lieu d'attendre le minuteur (5 min) — reconnexion WS déclenche aussi une synchro immédiate côté app
  - le signal porte la liste des types réellement modifiés (`entities: [...]`) — l'app ne relit que ces types (ventes, produits, achats, dettes, clients, rabais, paliers de prix, paramètres) au lieu d'une resynchro complète ; type inconnu ou absent = resynchro complète par sécurité
  - signaux WS scopés par dépôt — une connexion ne reçoit que les signaux de son/ses dépôt(s) (liste de l'utilisateur, ou dépôt de l'installation locale)
  - serveur local → appareils : notifie ses propres clients WS dès qu'un pull a appliqué des données (paramètres, produits, clients, ventes, achats, dettes, rabais, paliers)
  - réglages (devise, taux, etc.) relus après chaque synchronisation terminée et dès le signal WebSocket, sans attendre la synchro complète — auparavant nécessitait un redémarrage de l'app pour apparaître
- [x] **Fiabilité hors-ligne** (`OfflineQueueService`) :
  - plus aucune opération abandonnée automatiquement après N échecs — reste en file jusqu'à réussir ; connectivité réseau réelle vérifiée avant toute tentative ; dédoublonnage par contenu au chargement et à l'ajout ; `drain()` réentrant (protégé contre les déclenchements concurrents)
  - écran "Opérations hors-ligne en attente" : détail de chaque opération, resynchro manuelle (globale ou par ligne), suppression définitive après confirmation explicite
  - idempotence `client_id` sur ventes, clients **et** achats (évite les doublons au rejeu), sur Android **et** bureau/web
  - fermeture de session de caisse mise en file hors-ligne comme une vente (restait silencieusement "ouverte" côté serveur sinon)
  - vente hors-ligne : horodatage réel envoyé par le client (`created_at`), au lieu de la date de la synchro différée
  - clients : déduplication à l'affichage (par nom), avertissement avant de créer un doublon, rejet serveur (409) sauf confirmation explicite

### 3.15 Identité serveur Ed25519

- [x] Clé privée Ed25519 (`IDENTITY_PRIVATE_KEY`) dans `pos_server.ini`
- [x] Clé publique hardcodée dans Flutter (`AppConstants.identityPublicKeyB64`)
- [x] `GET /api/public/identity?nonce=` — signe `{app}:{nonce}` → retourne signature base64
- [x] Wizard vérifie l'identité avant connexion tenant (protection anti-imposteur)

### 3.16 Cache de licence offline

- [x] `LicenseService` Flutter : serveur → fallback cache `FlutterSecureStorage`
- [x] Signature Ed25519 vérifiée côté Flutter
- [x] `AppShell` : `allowed` / `warning` / `blocked` selon `LicenseStatus.access`
- [x] Grâce offline : 7j (blob) + 3j = 10j max sans internet

### 3.17 Gestion des erreurs côté Flutter

- [x] `extractErrorMessage(DioException)` — priorité :
  1. Message spécifique du serveur (`data['detail']` ou `data['message']`) — si non vide et non générique (ex: "Internal Server Error" ignoré)
  2. Fallback par code HTTP en français : 400 → données invalides, 401 → session expirée, 403 → permission, 404 → introuvable, 409 → existe déjà, 422 → données invalides, 500 → erreur interne, 503 → indisponible
  3. Erreur réseau : timeout / connexion perdue
- [x] `extractAnyError(Object)` : wrapper acceptant `DioException` ou `Exception` générique (strip préfixe `"Exception: "` automatique)
- [x] Appliqué sur : tous les catch blocks flutter — `warehouses_screen`, `products_screen`, `returns_screen`, `inventory_screen`, `return_provider`, `pos_screen`, `sales_screen`, `open_session_dialog`, `installer_screen`

### 3.18 Cache local SQLite avec invalidation automatique

- [x] `OfflineCacheService.syncAll(warehouseId, tenantId)` compare tenant+warehouse avec les valeurs stockées en `SharedPreferences` (`_cache_tenant_id` / `_cache_warehouse_id`)
- [x] Si tenant ou warehouse a changé → `LocalDbService.clearAllCachedData()` vide toutes les tables locales avant de re-syncer
- [x] Évite la contamination de données entre comptes ou entre dépôts lors d'un changement de session
- [x] Sync utilisateurs offline filtrée par `warehouse_id` : `GET /api/users/offline-sync?warehouse_id=`
- [x] `users.offline_hash` en DB pour auth offline sans exposer le hash bcrypt
- [x] Version SQLite **13** : colonne `warehouse_id TEXT` ajoutée à la table `products` (migration `_onUpgrade` + `_createSchema` + `upsertProducts` + `_productFromRow`)

### 3.19 Préservation des deep links (router)

- [x] `pendingDeepLink` variable dans la closure `routerProvider`
- [x] `_kPublicRoutes` : ensemble de routes ne nécessitant pas d'auth
- [x] Pendant `isLoading=true` : si l'URL est protégée, elle est sauvegardée dans `pendingDeepLink` puis l'utilisateur est redirigé vers `/splash`
- [x] Après résolution auth : restaure `pendingDeepLink` (ou `/dashboard` par défaut)
- [x] Résultat : un refresh navigateur sur `/sales`, `/restaurant/tables`, etc. revient à la même page

### 3.20 Site public responsive

- [x] Barre de navigation (`PublicNavBar`) : 3 breakpoints — `≥860px` (nav complète), `500–860px` (CTA + hamburger), `<500px` (logo + hamburger uniquement)
- [x] Menu hamburger (`showModalBottomSheet`) : liens nav + boutons Se connecter / S'inscrire côte à côte
- [x] Texte héro responsive — `_HeroText` lit `MediaQuery.sizeOf(context).width` :
  - `≥900px` → 46px, `600–899px` → 34px, `400–599px` → 26px, `<400px` → 22px
- [x] Texte description responsive : 16px (≥600px) / 14px (<600px)
- [x] "Gérez votre Business." (remplace "commerce")
- [x] **Statistiques dynamiques** : les 3 chiffres du héro (commerces actifs, transactions/jour, disponibilité) sont lus depuis `platform_config` via `/api/public/pricing` — éditables par le superadmin, fallback hardcodé si API indisponible
  - `PlatformConfig` : colonnes `stat_businesses`, `stat_transactions_day`, `stat_uptime` (String, défauts `500+` / `10k+` / `99.9%`)
  - Migration `i9j0k1l2m3n4`
  - `_HeroText` converti en `ConsumerWidget`, lit `pricingProvider`

### 3.22 Factures et Devis (Proformas)

- [x] Modèle `Invoice` + `InvoiceItem` : référence auto, client, entête, TVA, remise, statut (`draft`/`sent`/`paid`/`cancelled`), `tenant_id`, `warehouse_id`
- [x] Modèle `Proforma` + `ProformaItem` : même structure qu'Invoice — document non contractuel / devis
- [x] `warehouse_id` optionnel sur les 4 tables (Invoice, InvoiceItem, Proforma, ProformaItem) — propagé automatiquement des entêtes aux lignes à la création et à la mise à jour
- [x] Migration `g7h8i9j0k1l2` — ajout `warehouse_id` sur `invoices`, `invoice_items`, `proformas`, `proforma_items` avec backfill
- [x] API CRUD `/api/invoices/` et `/api/proformas/` — création, lecture, mise à jour, suppression
- [x] Accès mobile caissier : route `/events` ouverte avec la permission `invoicesRead` (était `reportsReadAll`)
- [x] Entrée "Factures / Devis" ajoutée au menu de navigation pour tous les `business_type` (commerce, restaurant, hôtel)
- [x] PDF A4 Invoice : en-tête business, numéro de facture, section client, tableau articles (QTÉ / PRIX U. / TOTAL), totaux (HT, TVA, TTC), notes, pied de page
- [x] PDF A4 Proforma : même structure, badge bleu "DOCUMENT NON CONTRACTUEL — PROFORMA"
- [x] Bouton "Imprimer (A4)" avec spinner dans les dialogs aperçu Invoice et Proforma
- [x] Boutons de création conditionnels : `invoicesCreate` pour les factures, `proformasCreate` pour les devis

### 3.21 Mode Hôtel (en développement)

- [x] `room_attributes` table : attributs clé/valeur sur une chambre (type de lit, vue, étage, etc.) avec `warehouse_id`
- [x] `app_config.hotel_checkin_fields` (JSON) : champs personnalisés au check-in
- [x] `restaurant_tables.price` : tarif nuitée par chambre
- [x] `users.is_active` : activation/désactivation d'un utilisateur sans le supprimer

### 3.23 Vérification de l'heure de l'appareil

- [x] Heure du serveur lue dans l'en-tête `Date` de chaque réponse réseau, mémorisée sur l'appareil (`SharedPreferences`)
- [x] Bannière affichée au-delà de 2 minutes d'écart (en ligne) ou si l'heure de l'appareil recule par rapport à la dernière synchro connue (hors-ligne, vérifiable sans réseau)
- [x] Bouton "Encaisser" grisé tant que l'heure est fausse — la vente en cours n'est pas perdue
- [x] Désactivée sur le web (horloge du navigateur hors du contrôle de l'app)

### 3.24 Programme d'affiliation (parrainage)

- [x] Affiliés inscrits/vérifiés par email, code de parrainage transmis via `?ref=CODE` sur `/register`
- [x] Commission calculée automatiquement (`record_commission`) à chaque renouvellement de caisse confirmé
- [x] Demandes de retrait gérées depuis un onglet dédié du panel admin (`AffiliateCommission`, `AffiliateWithdrawal`)
- [x] Page `/parrainage` servie en statique, indépendante du build Flutter web

---

## 4. Schéma de base de données

```
tenants         ← gestionnaire SaaS
  │
  ├── users           categories      suppliers
  │     │                │               │
  │     │           products ────────────┘  ← warehouse_id optionnel
  │     │               │
  │     ├── sales ──────┤
  │     │     ├── sale_items
  │     │     ├── payments (reference_type=SALE)
  │     │     └── debts   (reference_type=SALE)
  │     │
  │     ├── purchases ──┤
  │     │     ├── purchase_items
  │     │     ├── purchase_receipts → purchase_receipt_items
  │     │     ├── payments (reference_type=PURCHASE)
  │     │     └── debts   (reference_type=PURCHASE)
  │     │
  │     ├── invoices ── warehouse_id
  │     │     └── invoice_items ── warehouse_id (hérité)
  │     │
  │     ├── proformas ── warehouse_id
  │     │     └── proforma_items ── warehouse_id (hérité)
  │     │
  │     └── restaurant_tables ──── waiter_id (FK users)
  │           └── restaurant_orders ── sale_id (FK sales)
  │                 └── restaurant_order_items ── product_id (FK products)
  │
  └── (toutes les tables métier ont tenant_id UUID FK)

stock_movements   ← lié à Product + User + source (sale/purchase/adjust)
app_config        ← paramètres persistants (business_type, devise, hotel_checkin_fields, etc.)
platform_config   ← config SaaS globale (numéros, prix, trial_days, admin hash, support_address)
billing_payments  ← historique paiements abonnements
sync_state        ← watermarks par entity_type
roles             ← rôles personnalisés par tenant
return_records    ← retours clients et fournisseurs
room_attributes   ← attributs clé/valeur des chambres hôtel (FK restaurant_tables)
```

**Tables restaurant / hôtel** :
- `restaurant_tables` : `tenant_id`, `warehouse_id`, `waiter_id`, `name`, `capacity`, `status`, `price`
- `restaurant_orders` : `tenant_id`, `table_id`, `cashier_id`, `status`, `covers`, `notes`, `tip`, `sale_id`
- `restaurant_order_items` : `order_id`, `product_id` (nullable), `menu_item_id`, `quantity`, `unit_price`, `notes`, `status`, `label`
- `menu_items` : `tenant_id`, `warehouse_id`, `name`, `description`, `price`, `category_id`, `variants` (JSON), `send_to_kitchen`
- `modifier_groups` : `tenant_id`, `warehouse_id`, `menu_item_id`, `name`, `required`, `max_choices`
- `room_attributes` : `tenant_id`, `table_id`, `warehouse_id`, `key`, `value`

**Colonnes ajoutées par migrations récentes** :
- `users.is_active` (bool, défaut `true`) — désactiver un utilisateur sans le supprimer
- `users.offline_hash` (string) — hash dédié à l'auth offline
- `sale_items.label` (string) — nom du plat (restaurant) conservé dans l'historique
- `invoices.warehouse_id`, `invoice_items.warehouse_id` — dépôt rattaché à la facture (migration `g7h8i9j0k1l2`)
- `proformas.warehouse_id`, `proforma_items.warehouse_id` — dépôt rattaché au devis/proforma (migration `g7h8i9j0k1l2`)
- `products.warehouse_id` — dépôt optionnel par produit (migration `h8i9j0k1l2m3`)

---

## 5. Bugs connus et points d'attention

### 5.1 Backend

| # | Statut | Problème |
|---|--------|----------|
| B1 | Résolu | `_is_setup_done` utilisait un filtre JSON incompatible MySQL → remplacé par `count()` |
| B2 | Résolu | `create-db` / `init` utilisaient le moteur global → moteur temporaire |
| B3 | Résolu | `pos_server.ini` écrit trop tard → maintenant écrit dès le test DB |
| B4 | Actif | `pos_server.ini` non rechargé en cours d'exécution → redémarrage requis après wizard |
| B5 | Résolu | Admin auth : `Auth.verify_password()` → utilise `pwdlib` directement |
| B6 | Résolu | Jours d'essai : `timedelta.days` (floor) → `math.ceil(delta.total_seconds() / 86400)` |
| B7 | Résolu | `trial_ends_at` non commité → commit explicite requis |
| B8 | Résolu | `No module named 'requests'` dans `local_sync_service` → remplacé par `httpx` |
| B9 | Résolu | MySQL "gone away" sur sessions longues → `pool_pre_ping + pool_recycle` |
| B10 | Résolu | Bug timezone sync : `datetime.now()` → `datetime.now(timezone.utc)` |
| B11 | Résolu | `list_tables` excluait les caissiers (check `_is_manager`) → corrigé : `'serveur' in roles` |
| B12 | Résolu | MySQL 1292 sur `POST /api/warehouses/{id}/registers` — colonnes `trial_ends_at` / `subscription_*_at` restées `DATETIME` alors que les valeurs Fernet sont du TEXT → migration `s5t6u7v8w9x0` estampillée sans avoir tourné → correction directe SQL + migration idempotente `f8bf3dfe3543` |
| B13 | Résolu | Alembic multiple heads — révision `a1b2c3d4e5f6` dupliquée → renommée `f3930ab198e9` + merge `00d25d56df77` |
| B14 | Résolu | Logo/uploads jamais accessibles publiquement en prod — nginx ne proxyait pas `/static/` vers FastAPI, `try_files` retombait sur le SPA → bloc `location /static/` ajouté (`pos.infini-software.cloud.nginx.conf`) |
| B15 | Résolu | Windows : dépendance de service `POS_Connect_API` → `POS_Connect_MySQL` (nssm `DependOnService`) posée uniquement à l'install fraîche, jamais réappliquée sur réinstallation/mise à jour → si l'API démarre avant MySQL au boot, `_ensure_db_ready()` bascule silencieusement et définitivement sur SQLite (`db_type: sqlite`, `setup_done: false`) même avec `pos_server.ini` correctement configuré en mysql. Corrigé : dépendance posée à chaque exécution (`setup-info/setup-windows.ps1`) |
| B16 | Résolu | `pos_server.ini` illisible (permissions/verrou) → `configparser.read()` échoue en silence total, aucune trace dans les logs → log explicite ajouté (`api/core/config.py`) |
| B17 | Actif | Fichiers uploadés (`api/static/logos/*`) disparaissent entre deux déploiements prod — cause exacte non confirmée (probable étape de déploiement qui réinitialise `/opt/post` aux fichiers trackés par git, or ces uploads ne sont pas versionnés) — à investiguer côté script de déploiement |
| B18 | Ajouté | `CORS_ORIGIN_REGEX` (optionnel, vide par défaut) en complément de `CORS_ORIGINS` — permet `flutter run -d chrome` en local contre un backend sans lister un port exact à chaque lancement |
| B19 | Résolu | **Critique** — `create_sale()` : `Decimal * float` levait `TypeError` dès qu'une vente atteignait réellement un palier de prix (jamais détecté : seul `tier_price()` isolé était testé, jamais `create_sale()` avec une quantité franchissant un seuil) → `float(tier)` à la conversion. Une fois ce crash corrigé, bug plus profond trouvé : le prix du palier n'était calculé que pour le total de la vente (1ère boucle) ; une 2de boucle, indépendante, recalculait son propre prix pour construire chaque `SaleItem` en ignorant totalement les paliers — total correct, mais chaque ligne vendue enregistrée au prix catalogue. Le prix calculé est maintenant mémorisé (`item_unit_prices`) et réutilisé tel quel pour les deux boucles |
| B20 | Résolu | `PriceTierIn`/`PriceTierRead` typés `Decimal` → Pydantic v2 sérialise en **chaîne JSON** (`"3.00"`, pas `3.00`) ; le client Flutter castait `min_quantity`/`price` en `num`, crash "Une erreur inattendue s'est produite" dès l'ouverture d'un produit ayant au moins un palier → schémas passés en `float` (`price_tier_service` reconvertit de toute façon en `Decimal` avant tout calcul, aucune perte de précision) |
| B21 | Résolu | Toute colonne ajoutée via `_sync_schema_from_models()` (seul mécanisme de migration sur une install locale *frozen*, Alembic y étant ignoré) ne touche jamais `updated_at` des lignes existantes — le curseur de pull local (basé sur `updated_at` côté cloud) ne les re-tirait donc plus jamais, la valeur par défaut de la nouvelle colonne restant figée localement pour toujours, même après mise à jour du serveur local (constaté : `Product.is_service` resté à `0` sur des produits déjà synchronisés avant l'ajout de la colonne) → toute table ayant reçu une nouvelle colonne déclenche désormais la réinitialisation du curseur de pull des entités concernées |
| B22 | Résolu | **Faille d'autorisation par dépôt** (confirmée en prod : vente d'un caissier assigné à un seul dépôt comptabilisée sur un autre business du même tenant, faussant la numérotation des deux) — `create_sale()` faisait confiance au `warehouse_id` envoyé par le client sans jamais le vérifier contre `User.warehouse_id` ; même faille non reproduite à `cloud_login()` et `open_session()` (appareil déjà lié à la caisse d'un autre dépôt réutilisé tel quel) ; `list_warehouses()` repliait aussi silencieusement sur tous les dépôts actifs si le dépôt assigné à un caissier restreint était introuvable → vérification ajoutée aux trois endroits, résolution du dépôt par priorité stricte (session de caisse ouverte > dépôt unique du caissier > jamais le défaut du tenant), rejet explicite (400/403) si ambigu plutôt qu'un repli silencieux |
| B23 | Résolu | Écran Profil (Informations personnelles) envoyait `phone`/`address` vides et un `email` factice en dur à chaque sauvegarde, alors qu'il n'affiche pas ces champs — écrasait silencieusement les vraies valeurs d'un utilisateur (et réactivait `is_active`) → champs omis du payload (`exclude_unset=True` côté backend préserve l'existant). Corrige aussi `_check_unique()` : la vérification d'unicité de l'email n'était pas filtrée par tenant — le premier utilisateur de N'IMPORTE QUEL tenant à sauvegarder son profil bloquait tous les autres tenants sur ce même email factice |
| B24 | Résolu | Synchro non scopée par dépôt : le cloud renvoyait à toute installation locale l'intégralité des données du tenant, tous dépôts confondus (voir 3.14) — fuite de données entre dépôts d'un même tenant multi-business |
| B25 | Résolu | `User.warehouse_id` (liste JSON) et la ligne `app_config` globale (`warehouse_id NULL`) étaient exclus à tort par le filtre de synchro par dépôt — aucun compte utilisateur ne remontait aux caisses, la configuration globale n'était jamais reçue |
| B26 | Résolu | WebSocket temps réel : jeton de synchro non migré vers le nouveau stockage sécurisé (connexion `/ws` abandonnée en silence), protocole non détecté automatiquement par uvicorn dans l'exécutable Windows compilé (404), nginx local sans en-têtes `Upgrade`/`Connection` sur `/ws` (404), signal de réveil effacé après plutôt qu'avant le cycle de synchro (signal reçu pendant une synchro perdu), routes de prix par dépôt/paliers n'envoyant aucun signal (changement visible seulement au minuteur, ~1 min) |
| B27 | Résolu | `GET /api/sessions/current` renvoyait, sans filtre par caissier, la session ouverte par N'IMPORTE QUEL AUTRE caissier sur la même caisse — donnait l'impression qu'une session restait ouverte alors que toutes celles de l'utilisateur connecté étaient fermées |
| B28 | Résolu | Fermeture de session de caisse (normale ou forcée) ne signalait rien aux autres appareils — caisse et écran Audit gardaient l'ancien état jusqu'à une navigation ou le minuteur |
| B29 | Résolu | Une installation ayant créé sa propre ligne `app_config` (avant son premier pull) recevait ensuite celle du cloud — même tenant/dépôt, identifiant différent — et se retrouvait avec deux lignes au lieu d'une mise à jour ; l'app pouvait lire l'ancienne ligne (jamais mise à jour) selon celle que `/api/config` choisissait |

### 5.2 Frontend

| # | Statut | Problème |
|---|--------|----------|
| F1 | Résolu | URL serveur sauvegardée à chaque test → uniquement à la fin du wizard |
| F2 | Résolu | Wizard lisait SharedPreferences stale → reset à `AppConstants.baseUrl` |
| F3 | Résolu | Images produits URL hardcodée → `dio.options.baseUrl` (runtime) |
| F4 | Résolu | `Platform._operatingSystem` crash sur web → guards `!kIsWeb` |
| F5 | Résolu | Bouton "Lancer POS Connect" inactif → navigate vers `/login` |
| F6 | Actif | Redémarrage serveur non automatique après wizard desktop |
| F7 | Résolu | Panel admin "Erreur de chargement" → colonnes `moncash_mode`/`natcash_mode` manquantes |
| F8 | Résolu | Données admin non rafraîchies après save → `_loaded = false` manquant |
| F9 | Résolu | Section sync invisible → condition `tenant == null` supprimée |
| F10 | Résolu | Splash affiché à chaque reprise → fast-path si JWT présent |
| F11 | Résolu | 403 retours caissier → permission `returns.create` ajoutée au rôle cashier |
| F12 | Résolu | Erreur DioException brute affichée → `extractAnyError` localisé |
| F13 | Résolu | Flash splash au login → `refreshListenable` dans `routerProvider` |
| F14 | Résolu | Menu Abonnement absent sur web → guard `kIsWeb || isAdmin` |
| F15 | Résolu | `_buildFullDrawerItems` wrong arg count → 5ème param `businessType` ajouté |
| F16 | Résolu | Plats vides sur mobile → filtre `warehouse_id` retiré de `getMenuItems()` (plats tenant-wide) |
| F17 | Résolu | Refresh navigateur perd l'URL → `pendingDeepLink` + `_kPublicRoutes` dans `router.dart` |
| F18 | Résolu | Menu hamburger absent site public mobile → `showModalBottomSheet` + 3 breakpoints |
| F19 | Résolu | Texte héro taille fixe → responsive (46/34/26/22px) + "Business" |
| F20 | Résolu | Cache local contaminé au changement de compte → invalidation tenant/warehouse dans `syncAll()` |
| F21 | Résolu | `warehouse_id` produit absent de SQLite → perte silencieuse (sqflite ignore les clés inconnues) → v13 : schema + upsert + reader mis à jour |
| F22 | Résolu | Factures/Devis inaccessibles aux caissiers → permission `reportsReadAll` → `invoicesRead`, nav ajoutée à tous les menus |
| F23 | Résolu | Dialog Proforma sans impression → `_buildProformaPdf` A4 ajouté + `_ProformaPreviewDialog` converti en `StatefulWidget` |
| F24 | Résolu | Bouton "Télécharger" dans `_ForceUpdateScreen` vide (`onPressed: () {}`) → branché sur `launchUrl` |
| F25 | Résolu | Bandeau `_UpdateBanner` sans bouton téléchargement → ajouté avec sélection Android/Desktop |
| F26 | Résolu | `e.toString()` affiché brut dans `warehouses_screen`, `products_screen`, `returns_screen`, `inventory_screen`, `return_provider` → `extractAnyError(e)` |
| F27 | Résolu | Web pouvait réclamer une caisse physique juste en affichant l'onglet POS/Commandes (device_id généré localement, aucun appareil réel) → web ne peut plus ouvrir de session caisse (`pos_screen`, `commandes_screen`, `checkDevicePendingApproval`), message dédié vers l'app bureau/mobile |
| F28 | Résolu | Bannière "Nouvelle version disponible" et écran de mise à jour obligatoire (`_ForceUpdateScreen`, plein écran, sans bouton retour) s'affichaient même sans lien de téléchargement pour la plateforme courante → masqués si `resolveUpdateDownloadUrl` retourne vide (web excepté) |
| F29 | Résolu | Nom/téléphone/NIF client wrappait caractère par caractère sur écran étroit (`_CustomerCard` sans `maxLines`/`overflow`, `trailing` trop large) → `maxLines: 1` + `TextOverflow.ellipsis` partout dans la carte |
| F30 | Résolu | Logo entreprise jamais affiché sur l'écran Profil même après upload réussi — `Image.network(settings.logoPath, ...)` utilisait un chemin relatif, sans `errorBuilder` → URL absolue via `dio.options.baseUrl` + fallback icône |
| F31 | Résolu | Upload logo (`POST /api/config/logo`) n'envoyait pas `warehouse_id` (contrairement à `_load()`/`save()`) → pouvait atterrir sur une ligne `AppConfig` différente de celle affichée à l'écran (dépôt par défaut de l'utilisateur ≠ business sélectionné) |
| F32 | Résolu | Logo jamais imprimé sur reçu via imprimante Sunmi intégrée (seuls PDF et Bluetooth l'avaient) → `SunmiPrinter.printImage()` ajouté dans `thermal_printer_service.dart` |
| F33 | Résolu | Modal "Modifier le produit" : écran gris (aucun champ affiché) uniquement en build `--release`/web déployé, jamais en `--debug` → `Spacer()` (= `Expanded` déguisé) dans `AlertDialog.actions`, mis en page par un `OverflowBar` depuis Flutter 3.x (pas un `Row`) → `TypeError: _OverflowBarParentData is not a subtype of FlexParentData` ; actions enveloppées dans un `Row` dédié |
| F34 | Résolu | Formulaire produit : prix produit/par-dépôt/paliers lisait `settingsProvider` à deux moments différents (préremplissage à l'ouverture, conversion à l'enregistrement) — un changement de devise/taux pendant que le formulaire restait ouvert (ex: poussé en temps réel depuis un autre appareil) corrompait silencieusement le prix enregistré sans y toucher (constaté : prix saisi à 20 ressorti à 0.77 après réouverture/réenregistrement sans modification) → devise figée une seule fois à l'ouverture (`_formSettings`), réutilisée telle quelle jusqu'à la fermeture |
| F35 | Résolu | **Critique** — Caisse : `CartItem.tiers` figé à l'ajout au panier (`_tiersOf(ref, ...)` lit `priceTiersProvider` une seule fois via `ref.read`) — si le `FutureProvider` n'avait pas fini de charger (ouverture de caisse, changement de dépôt), l'article gardait `tiers=[]` pour toute sa durée de vie dans le panier, même une fois les paliers chargés juste après : prix normal affiché au lieu du prix en gros, risque de sous-encaissement → `PosNotifier.refreshTiers()` rattrape chaque article déjà présent dès que `priceTiersProvider` se (re)charge, sans jamais écraser un prix déjà modifié manuellement |
| F36 | Résolu | Écran Produits : clic sur une ligne du tableau ouvrait directement le formulaire d'édition (pas de fiche détails en lecture seule) → nouvelle `_ProductDetailsDialog` (texte simple, bouton "Modifier" séparé) ; même comportement appliqué à la carte mobile (`onTap`) |
| F37 | Résolu | Verrou produit (cadenas) inaccessible sur mobile — uniquement dans le tableau desktop ; débordement (`RIGHT OVERFLOWED`) de la barre d'actions du dialogue "Modifier" sur mobile |
| F38 | Résolu | Reçu imprimé avec l'identité (nom/logo/devise/taxe) du dépôt **actif dans l'UI** de l'appareil au lieu du dépôt **réel de la vente**, sur un tenant multi-business — notamment juste après l'encaissement et à la réimpression depuis l'historique → résolution depuis `warehouse_id` de la vente, pas celui affiché à l'écran |
| F39 | Résolu | Commande ESC 7 (réglage chaleur imprimante thermique) imprimait un caractère parasite ("u") en tête de reçu sur certains clones ESC/POS ne la supportant pas — retirée, le double-strike + bold déjà actifs suffisent |
| F40 | Résolu | Écran Rapport (notamment mobile) appelait l'API directement, contournant le repli Android vers le cache SQLite — échouait systématiquement hors connexion au lieu d'afficher les données déjà en cache |
| F41 | Résolu | Réglages (devise, taux de change) non relus après une synchronisation — un changement poussé depuis le cloud n'apparaissait qu'après redémarrage de l'app |
| F42 | Résolu | Message 403 générique ("Abonnement suspendu ou expiré") affiché à la connexion quelle que soit la vraie cause serveur — masquait notamment le refus "appareil déjà lié à un autre dépôt" (voir B22) sous un message trompeur |
| F43 | Résolu | Dépôt actif pouvait rester bloqué sur "tous les dépôts" après une déconnexion forcée (session expirée), y compris pour un caissier restreint à un seul dépôt — drapeau persistant (`SharedPreferences`) survivant même à une réinstallation complète de l'app |

---

## 6. Déploiement

### 6.1 Serveur (Debian/Ubuntu recommandé, Docker)

```bash
cd /opt/post/fastapi
git pull origin main
docker compose down && docker compose up -d --build
```

### 6.2 Migrations après mise à jour

```bash
docker exec pos_api alembic upgrade head
docker restart pos_api
```

Migrations récentes :
- `o9p0q1r2s3t4` — `warehouse_id` sur `app_config`
- `p0q1r2s3t4u5` — tables `restaurant_tables`, `restaurant_orders`, `restaurant_order_items`
- `q1r2s3t4u5v6` — `waiter_id` sur `restaurant_tables`, `covers`/`tip` sur `restaurant_orders`
- `r2s3t4u5v6w7` — `restaurant_orders.table_id` nullable (commandes sans table)
- `s3t4u5v6w7x8` — `menu_items.variants`(JSON), `menu_items.warehouse_id`, `restaurant_order_items.menu_item_id`, `modifier_groups.menu_item_id`/`warehouse_id`, `users.offline_hash`
- `t4u5v6w7x8y9` — `menu_items.send_to_kitchen` (bool, défaut `true`)
- `u5v6w7x8y9z0` — `sale_items.label` (nom plat dans historique)
- `v6w7x8y9z0a1` — `users.is_active` (bool, défaut `true`)
- `w7x8y9z0a1b2` — `platform_config.support_address`
- `x8y9z0a1b2c3` — table `room_attributes` (mode hôtel)
- `y9z0a1b2c3d4` — `app_config.hotel_checkin_fields`, `room_attributes.warehouse_id`
- `z0a1b2c3d4e5` — `restaurant_tables.price` (tarif nuitée chambre)
- `g7h8i9j0k1l2` — `warehouse_id` sur `invoices`, `invoice_items`, `proformas`, `proforma_items` (avec backfill)
- `h8i9j0k1l2m3` — `warehouse_id` sur `products`
- `i9j0k1l2m3n4` — `stat_businesses`, `stat_transactions_day`, `stat_uptime` sur `platform_config`
- `f3930ab198e9` — `update_url_android` sur `platform_config` (lien Google Play)
- `00d25d56df77` — merge de toutes les têtes Alembic divergentes (11 heads → 1)
- `f8bf3dfe3543` — correctif idempotent `pos_registers.*_at` DATETIME → TEXT(600) (Fernet)
- `e7c1a9d2f4b8` — `discounts.warehouse_id` (rabais par dépôt, `NULL` = tous les dépôts) — fusionne deux têtes Alembic divergentes
- `f3a8d1c6e2b9` — table `product_price_tiers` (paliers de prix par dépôt)
- `a1b4c7d9e3f2` — `products.is_service` (type "service", défaut `false`)

### 6.3 Client (autre machine)

1. Copier `pos_connect` sur la machine cliente
2. Lancer l'app → wizard → Mode "Client uniquement"
3. Entrer l'URL du serveur (ex: `http://192.168.0.110:8002`)

### 6.4 Build CI/CD

GitHub Actions sur chaque push vers `main` :
- `pos_connect-linux.tar.gz`
- `pos_connect-windows.zip`
- `pos_connect-macos.zip`
- `pos_connect-android.apk`

---

## 7. Configuration

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
host                  = 0.0.0.0
port                  = 8002
secret_key            = <généré automatiquement>
token_expire_minutes  = 480
admin_email           = admin@posconnect.ht
admin_password_hash   = $argon2id$v=19$...
cloud_sync_url        =
cloud_sync_token      =
cloud_sync_enabled    = false
billing_url           =
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

## 8. Prochaines étapes

| Priorité | Feature |
|----------|---------|
| Haute | Finaliser mode Hôtel : check-in/check-out, attributs chambre, tarification nuitée |
| Haute | Rechargement automatique de `pos_server.ini` sans redémarrage |
| Haute | Intégration API MonCash / NatCash (mode `api_auto`) |
| Haute | Portail self-service tenant (upgrade plan, voir caisses) |
| Haute | Activation/désactivation utilisateur UI (utiliser `users.is_active`) |
| Haute | Identifier pourquoi `api/static/logos/*` disparaît entre deux déploiements prod (voir B17) — rendre les uploads persistants indépendamment du script de déploiement |
| Moyenne | Impression tickets thermiques (reçus de ventes, mode restaurant — `printing` package) |
| Moyenne | Dashboard statistiques complet (ventes/jour, top produits) |
| Moyenne | Page de configuration URL serveur sur web (remplace le wizard) |
| Moyenne | Factures récapitulatives mensuelles par tenant |
| Moyenne | Variantes de plats UI (exploiter `menu_items.variants` JSON) |
| Moyenne | Envoi facture/proforma par email depuis l'app |
| Basse | Mode inventaire restaurant (recettes, coûts matières) |
| Basse | Saisie libre d'un prix personnalisé par ligne en caisse — logique déjà prête côté provider (`PosNotifier.updateItemPrice`) mais jamais câblée à un champ dans l'UI |
| Basse | Réservations de tables / chambres (heure, nom client) |
| Basse | Tests unitaires backend (pytest) |
| Basse | Migration SQLite → MySQL |
