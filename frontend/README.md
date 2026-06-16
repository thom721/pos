# POS Connect — Frontend Flutter

Application multi-plateforme du système de caisse POS Connect.

## Plateformes supportées

| Plateforme | Statut |
|------------|--------|
| Linux | Production (build GitHub Actions) |
| Windows | Production (build GitHub Actions) |
| macOS | Production (build GitHub Actions) |
| Android | Production (APK GitHub Actions) |
| Web/Chrome | Supporté (client uniquement) |

## Lancer en développement

```bash
flutter run -d linux     # Desktop Linux
flutter run -d chrome    # Navigateur web
flutter run -d macos     # Desktop macOS
flutter run -d <device>  # Android connecté
```

## Architecture

- **État** : Riverpod (`StateProvider`, `FutureProvider`, `ConsumerWidget`)
- **Navigation** : go_router
- **HTTP** : Dio (singleton `dio` dans `api_client.dart`, `baseUrl` dynamique)
- **Persistance URL** : SharedPreferences (`server_url`)
- **Persistance licence** : `flutter_secure_storage` (`license_data`, `license_sig`)
- **Crypto** : package `cryptography` (Ed25519 — vérification identité serveur + licence)

## Flux de démarrage

```
main() → initServerUrl() → SplashScreen → health check
  ├── setup_done: false + desktop  →  /install (wizard)
  ├── setup_done: false + web      →  /login
  └── setup_done: true             →  /dashboard (ou /login si non connecté)
```

## Wizard d'installation (étapes)

1. Bienvenue
2. Choix mode (Serveur / Client / Les deux)
3. Adresse serveur + test connexion
4. Base de données (MySQL / SQLite)
5. Configuration MySQL
6. **Compte cloud** — connexion tenant posconnect.ht
   - Vérification identité Ed25519 du serveur (anti-usurpation)
   - Détection automatique `tenant_type` : `shared` ou `selfhosted`
7. Installation (`create-db` + `connect-tenant`)
8. Terminé

## URL serveur

L'URL est gérée en deux niveaux :
- **Runtime** : `dio.options.baseUrl` (mis à jour par `saveServerUrl()`)
- **Persistance** : SharedPreferences clé `server_url`

Le wizard ne touche pas SharedPreferences pendant les tests. L'URL est persistée **une seule fois à la fin**.

## Licence offline (`LicenseService`)

- Vérifie le statut d'abonnement à chaque démarrage
- Essaie d'abord le serveur → cache signé si offline
- Signature Ed25519 vérifiée avec `AppConstants.identityPublicKeyB64` (hardcodé)
- Grâce offline : 7 jours + 3 jours = 10 jours max sans internet
- `AppShell` affiche bannière ou bloque selon `LicenseAccess`
- `clearCache()` appelé au logout

## Variables de compilation

```dart
// frontend/lib/core/constants.dart
static const _serverIp = '192.168.0.110';      // IP par défaut compilée
static String get baseUrl => 'http://$_serverIp:8002';
static const cloudUrl = 'http://192.168.0.110:8002'; // TODO: remplacer par VPS
static const identityPublicKeyB64 = 'xH5c/...'; // clé publique Ed25519 posconnect.ht
```

Changer `_serverIp` et `cloudUrl` avant compilation pour la production.
