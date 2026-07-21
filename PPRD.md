# PPRD — Product & Project Requirements Document
# POS Connect — Système de Caisse Multi-Plateforme

**Date :** 2026-07-21
**Version :** 0.9 (en développement actif)
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

### 3.4 Ventes

- [x] Création vente avec lignes (SaleItem)
- [x] Vérification stock avant vente
- [x] Mouvements stock OUT automatiques
- [x] Enregistrement paiement (CASH / BANK / MOBILE)
- [x] Création dette automatique si paiement partiel
- [x] Statuts : UNPAID / PAID / PARTIAL
- [x] Annulation de vente
- [x] Retour client (permission `returns.create` accordée aux caissiers)

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

### 3.13 Facturation et abonnements

- [x] `GET /api/billing/status` : jours restants, statut, `is_grace`, `grace_days_left`
- [x] `GET /api/billing/config` : numéros, prix, modes MonCash/NatCash
- [x] `GET /api/billing/caisse-count` : caisses actives vs max_caisses, montant facturation extra
- [x] `GET /api/billing/license` : blob JSON signé Ed25519 (valide 7 jours)
- [x] Cycle de vie : **trial** → **expired** (grâce 10j) → **suspended** → **active**
- [x] Bannière orange "période de grâce" dans l'écran facturation Flutter
- [x] Menu "Abonnement" visible pour admins sur web et desktop (via `kIsWeb` + rôle)

### 3.14 Synchronisation local ↔ cloud

- [x] `POST /api/sync/token` — credentials tenant → JWT sync (365j)
- [x] `POST /api/sync/push` / `GET /api/sync/pull` — upsert bidirectionnel
- [x] `POST /api/sync/run` — cycle complet
- [x] Table `SyncState` : watermarks par entity_type
- [x] Entités bidirectionnelles : `category`, `supplier`, `product`, `customer`
- [x] Entités push-only : `sale`, `sale_item`, `payment`, `purchase`, `return_record`
- [x] Résolution conflits : last-write-wins sur `updated_at`
- [x] Bug timezone corrigé : `datetime.now()` (local) remplacé par `datetime.now(timezone.utc)` pour éviter les comparaisons incohérentes

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

- [x] `extractErrorMessage(DioException)` : 403 → message permission, 401 → session expirée, 503 → service indisponible, sinon `data['message']` ou `data['detail']`
- [x] `extractAnyError(Object)` : wrapper acceptant n'importe quelle exception
- [x] Appliqué sur : écran retours, écran admin, paramètres, changement mot de passe, restaurant

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
| Moyenne | Impression tickets thermiques (reçus de ventes, mode restaurant — `printing` package) |
| Moyenne | Dashboard statistiques complet (ventes/jour, top produits) |
| Moyenne | Page de configuration URL serveur sur web (remplace le wizard) |
| Moyenne | Factures récapitulatives mensuelles par tenant |
| Moyenne | Variantes de plats UI (exploiter `menu_items.variants` JSON) |
| Moyenne | Envoi facture/proforma par email depuis l'app |
| Basse | Mode inventaire restaurant (recettes, coûts matières) |
| Basse | Réservations de tables / chambres (heure, nom client) |
| Basse | Tests unitaires backend (pytest) |
| Basse | Migration SQLite → MySQL |
