import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/core/router.dart' show routerProvider, appNavigatorKey;
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/providers/sync_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';
import 'package:pos_connect/services/offline_cache_service.dart';
import 'package:pos_connect/services/offline_queue_service.dart';
import 'package:pos_connect/services/websocket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Android: WebSocket for real-time push + 2-min fallback timer
// Desktop/Web: 5-min polling timer only
const _kAndroidFallbackInterval = Duration(minutes: 2);
const _kDesktopSyncInterval = Duration(minutes: 5);

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class PosApp extends ConsumerStatefulWidget {
  const PosApp({super.key});

  @override
  ConsumerState<PosApp> createState() => _PosAppState();
}

class _PosAppState extends ConsumerState<PosApp> {
  late final StreamSubscription<String?> _authSub;
  late final StreamSubscription<OfflineQueueItem> _droppedSub;
  Timer? _syncTimer;
  Timer? _heartbeatTimer;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _authSub = onUnauthorized.listen((message) async {
      // Generic credential errors (bad login attempt) skip the dialog.
      const kGeneric = 'Could not validate credentials';
      final showReason = message != null && message != kGeneric;
      await _forceLogout(showReason ? message : null);
    });
    _droppedSub = OfflineQueueService.dropped.listen((item) {
      _messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text(
          'Opération hors-ligne perdue : ${item.method} ${item.path}',
        ),
        backgroundColor: Colors.orange[800],
        duration: const Duration(seconds: 5),
      ));
    });
  }

  /// Déconnexion forcée avec dialogue optionnel (raison serveur ou changement
  /// de permissions). Réutilisé par le 401 générique et par le push WebSocket
  /// "permissions_changed".
  Future<void> _forceLogout(String? message) async {
    _stopAutoSync();
    if (message != null) {
      final ctx = appNavigatorKey.currentContext;
      if (ctx != null) {
        // ctx is the root GoRouter navigator context — it outlives any route
        // change, so the async-gap lint is a false positive here.
        await showDialog<void>(
          // ignore: use_build_context_synchronously
          context: ctx,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Session terminée'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
    ref.read(authProvider.notifier).logoutDueToExpiry();
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    // Immédiat, indépendant du reste du cycle de sync — _triggerSync()
    // attend que tenantProvider soit résolu avant de vérifier l'approbation
    // (voir plus bas), ce qui n'est presque jamais le cas juste après une
    // connexion : le tout premier appel se retrouvait silencieusement sauté,
    // repoussant la détection au prochain cycle (jusqu'à 2 min sur Android).
    checkDevicePendingApproval(ref).ignore();
    _triggerSync();
    if (_isAndroid) {
      WebSocketService.instance.start(
        _triggerSync,
        onPermissionsChanged: () => _forceLogout(
          'Vos permissions ont été modifiées par un administrateur — veuillez vous reconnecter.',
        ),
      );
      _syncTimer = Timer.periodic(_kAndroidFallbackInterval, (_) => _triggerSync());
    } else {
      _syncTimer = Timer.periodic(_kDesktopSyncInterval, (_) => _triggerSync());
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _sendHeartbeat(),
    );
    _sendHeartbeat();
  }

  void _stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    WebSocketService.instance.stop();
  }

  Future<void> _sendHeartbeat() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(AppConstants.deviceIdKey);
    if (deviceId == null) return;
    try {
      await dio.post(
        '/api/warehouses/registers/heartbeat',
        data: {'device_id': deviceId},
        options: kBackgroundOptions,
      );
    } catch (_) {
      // Non-fatal: heartbeat failures don't interrupt the user
    }
  }

  Future<void> _triggerSync() async {
    try {
      // 1. Rejouer les mutations en attente
      final replayed = await OfflineQueueService.instance.drain(dio);
      if (replayed > 0) {
        debugPrint('[AutoSync] offline queue drained: $replayed opération(s) rejouée(s)');
      }
      // 2. Sync bidirectionnelle avec le cloud
      await dio.post('/api/sync/run', options: kBackgroundOptions);
    } catch (e) {
      debugPrint('[AutoSync] cloud sync error: $e');
    }
    // 3. Rafraîchir le cache SQLite local
    // activeWarehouseProvider peut être null au 1er démarrage (avant que la liste
    // soit chargée). On se rabat alors sur le 1er warehouse assigné à l'utilisateur.
    final warehouseId = ref.read(activeWarehouseProvider)?.id
        ?? ref.read(authProvider).user?.warehouseIds.firstOrNull;
    final tenant = ref.read(tenantProvider).valueOrNull;
    final tenantId = tenant?['id'] as String?;
    final businessType = ref.read(settingsProvider).businessType;
    // Vérifié app-wide, pas seulement sur l'écran Caisse — l'utilisateur doit
    // voir la bannière même s'il ne visite jamais cet onglet (fire-and-forget,
    // ne doit jamais bloquer le reste du cycle de synchro). Pas de garde sur
    // tenantId : l'appel (/api/sessions/current) n'en a pas besoin — le
    // tenant est résolu côté serveur via le JWT — et ce garde faisait sauter
    // silencieusement le tout premier appel juste après connexion (voir
    // _startAutoSync, qui appelle déjà cette même fonction immédiatement).
    checkDevicePendingApproval(ref, warehouseId: warehouseId).ignore();
    if (_isAndroid) {
      // Android : attendre la fin de la sync SQLite avant de notifier les providers
      // (les repos lisent depuis SQLite, il faut que le cache soit à jour)
      await OfflineCacheService.instance.syncAll(
          warehouseId: warehouseId,
          tenantId: tenantId,
          businessType: businessType);
      if (mounted) {
        ref.read(syncEpochProvider.notifier).state++;
      }
    } else {
      // Bureau / Web : fire-and-forget, puis notifier les providers une fois terminé
      // (les repos lisent l'API directement, pas SQLite, donc le refresh déclenche
      // simplement un rechargement API — correct et non bloquant)
      OfflineCacheService.instance.syncAll(
          warehouseId: warehouseId,
          tenantId: tenantId,
          businessType: businessType)
        .whenComplete(() {
          if (mounted) ref.read(syncEpochProvider.notifier).state++;
        }).ignore();
    }
  }

  @override
  void dispose() {
    _authSub.cancel();
    _droppedSub.cancel();
    _stopAutoSync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Start/stop auto-sync based on auth state
    final isLoggedIn = ref.watch(authProvider).isAuthenticated;
    if (isLoggedIn && _syncTimer == null) {
      _startAutoSync();
    } else if (!isLoggedIn && _syncTimer != null) {
      _stopAutoSync();
    }

    return MaterialApp.router(
      title: 'POS Connect',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: AppTheme.light,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr'), Locale('en')],
      locale: const Locale('fr'),
    );
  }
}
