import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/services/offline_queue_service.dart';

// ── Status ────────────────────────────────────────────────────────────────────

final syncStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await dio.get('/api/sync/status');
  return res.data as Map<String, dynamic>;
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class SyncState {
  final bool isRunning;
  final bool isConfiguring;
  final String? lastResult;
  final String? error;

  const SyncState({
    this.isRunning = false,
    this.isConfiguring = false,
    this.lastResult,
    this.error,
  });

  SyncState copyWith({
    bool? isRunning,
    bool? isConfiguring,
    String? lastResult,
    String? error,
  }) =>
      SyncState(
        isRunning: isRunning ?? this.isRunning,
        isConfiguring: isConfiguring ?? this.isConfiguring,
        lastResult: lastResult ?? this.lastResult,
        error: error,
      );
}

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  SyncNotifier(this._ref) : super(const SyncState());

  Future<bool> configure({
    required String cloudUrl,
    required String email,
    required String password,
    String deviceId = 'default',
  }) async {
    state = state.copyWith(isConfiguring: true, error: null);
    try {
      await dio.post('/api/sync/configure', data: {
        'cloud_url':   cloudUrl,
        'owner_email': email,
        'password':    password,
        'device_id':   deviceId,
      });
      _ref.invalidate(syncStatusProvider);
      state = state.copyWith(
        isConfiguring: false,
        lastResult: 'Synchronisation configurée avec succès',
      );
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ??
          'Impossible de joindre le serveur cloud';
      state = state.copyWith(isConfiguring: false, error: msg);
      return false;
    } catch (_) {
      state = state.copyWith(isConfiguring: false, error: 'Erreur inattendue');
      return false;
    }
  }

  Future<bool> runSync() async {
    state = state.copyWith(isRunning: true, error: null, lastResult: null);
    try {
      final res = await dio.post('/api/sync/run');
      final data = res.data as Map<String, dynamic>;
      final pushed = (data['pushed'] as Map?)?.values.fold<int>(0, (s, v) => s + (v as int));
      final pulled = (data['pulled'] as Map?)?.values.fold<int>(0, (s, v) => s + (v as int));
      final errors = (data['errors'] as List?)?.length ?? 0;
      final msg = 'Envoyé: $pushed | Reçu: $pulled'
          '${errors > 0 ? ' | $errors erreur(s)' : ''}';
      _ref.invalidate(syncStatusProvider);
      state = state.copyWith(isRunning: false, lastResult: msg);
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ?? 'Sync échoué';
      state = state.copyWith(isRunning: false, error: msg);
      return false;
    } catch (_) {
      state = state.copyWith(isRunning: false, error: 'Erreur inattendue');
      return false;
    }
  }
}

final syncProvider =
    StateNotifierProvider<SyncNotifier, SyncState>((ref) => SyncNotifier(ref));

/// Number of operations queued locally while offline.
/// Refresh by invalidating this provider after each sync attempt.
final pendingOfflineCountProvider = FutureProvider.autoDispose<int>(
  (_) => OfflineQueueService.instance.pendingCount(),
);

/// Incrémenté après chaque sync SQLite réussie (Android uniquement).
/// Les providers Android le surveillent pour se rafraîchir automatiquement.
final syncEpochProvider = StateProvider<int>((ref) => 0);
