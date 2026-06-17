import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/router.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/services/offline_cache_service.dart';
import 'package:pos_connect/services/offline_queue_service.dart';

const _kSyncInterval = Duration(minutes: 5);

class PosApp extends ConsumerStatefulWidget {
  const PosApp({super.key});

  @override
  ConsumerState<PosApp> createState() => _PosAppState();
}

class _PosAppState extends ConsumerState<PosApp> {
  late final StreamSubscription<void> _authSub;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _authSub = onUnauthorized.listen((_) {
      ref.read(authProvider.notifier).logout();
      _stopAutoSync();
    });
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    // Warm-up immédiat du cache au login
    _triggerSync();
    _syncTimer = Timer.periodic(_kSyncInterval, (_) => _triggerSync());
  }

  void _stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> _triggerSync() async {
    try {
      // 1. Rejouer les mutations en attente
      final replayed = await OfflineQueueService.instance.drain(dio);
      if (replayed > 0) {
        debugPrint('[AutoSync] offline queue drained: $replayed opération(s) rejouée(s)');
      }
      // 2. Sync bidirectionnelle avec le cloud
      await dio.post('/api/sync/run');
    } catch (_) {
      // Erreurs de sync serveur non fatales
    }
    // 3. Rafraîchir le cache SQLite local (indépendant de la sync cloud)
    OfflineCacheService.instance.syncAll().ignore();
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
