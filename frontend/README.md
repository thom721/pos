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

- **État** : Riverpod (`StateProvider`, `ConsumerWidget`)
- **Navigation** : go_router
- **HTTP** : Dio (singleton `dio` dans `api_client.dart`, `baseUrl` dynamique)
- **Persistance URL** : SharedPreferences (`server_url`)

## Flux de démarrage

```
main() → initServerUrl() → SplashScreen → health check
  ├── setup_done: false + desktop  →  /install (wizard)
  ├── setup_done: false + web      →  /login
  └── setup_done: true             →  /dashboard (ou /login si non connecté)
```

## URL serveur

L'URL est gérée en deux niveaux :
- **Runtime** : `dio.options.baseUrl` (mis à jour par `saveServerUrl()`)
- **Persistance** : SharedPreferences clé `server_url`

Le wizard d'installation ne touche pas SharedPreferences pendant les tests. L'URL est persistée **une seule fois à la fin** du wizard avec l'URL confirmée.

## Variables de compilation

```dart
// frontend/lib/core/constants.dart
static const _serverIp = '192.168.0.110';  // IP par défaut compilée
static String get baseUrl => 'http://$_serverIp:8002';
```

Changer `_serverIp` avant compilation pour cibler un autre serveur par défaut.
