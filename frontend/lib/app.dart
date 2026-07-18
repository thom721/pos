import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/core/router.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/providers/sync_provider.dart';
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
  late final StreamSubscription<void> _authSub;
  Timer? _syncTimer;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _authSub = onUnauthorized.listen((_) {
      // Preserve cached user so offline recovery can restore the session
      ref.read(authProvider.notifier).logoutDueToExpiry();
      _stopAutoSync();
    });
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _triggerSync();
    if (_isAndroid) {
      WebSocketService.instance.start(_triggerSync);
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
    } catch (_) {
      // Erreurs de sync serveur non fatales
    }
    // 3. Rafraîchir le cache SQLite local + config dépôt
    if (_isAndroid) {
      // Sur Android : attendre la fin de la sync pour notifier les providers
      await OfflineCacheService.instance.syncAll();
      if (mounted) {
        ref.read(settingsProvider.notifier).reload().ignore();
        ref.read(syncEpochProvider.notifier).state++;
      }
    } else {
      OfflineCacheService.instance.syncAll().ignore();
      ref.read(settingsProvider.notifier).reload().ignore();
    }
  }

  @override
  void dispose() {
    _authSub.cancel();
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
