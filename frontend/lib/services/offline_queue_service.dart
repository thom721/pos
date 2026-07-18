import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pos_connect/data/api/api_client.dart' show kBackgroundOptions;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:pos_connect/services/local_db_service.dart';

// ── Item ─────────────────────────────────────────────────────────────────────

class OfflineQueueItem {
  final String id;
  final String method;
  final String path;
  final dynamic data;
  final DateTime timestamp;
  final int retries;

  const OfflineQueueItem({
    required this.id,
    required this.method,
    required this.path,
    required this.data,
    required this.timestamp,
    this.retries = 0,
  });

  OfflineQueueItem copyWith({int? retries}) => OfflineQueueItem(
        id: id,
        method: method,
        path: path,
        data: data,
        timestamp: timestamp,
        retries: retries ?? this.retries,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'path': path,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'retries': retries,
      };

  factory OfflineQueueItem.fromJson(Map<String, dynamic> json) =>
      OfflineQueueItem(
        id: json['id'] as String,
        method: json['method'] as String,
        path: json['path'] as String,
        data: json['data'],
        timestamp: DateTime.parse(json['timestamp'] as String),
        retries: (json['retries'] as int?) ?? 0,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class OfflineQueueService {
  static final OfflineQueueService instance = OfflineQueueService._();
  OfflineQueueService._();

  static const _prefKey     = 'offline_ops_queue_v1';
  static const _maxRetries  = 5;

  // Paths never queued offline (auth + sync endpoints)
  static const _skipPaths = [
    '/api/auth',
    '/api/login',
    '/api/public',
    '/api/sync',
    '/api/setup',
  ];

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<List<OfflineQueueItem>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList(_prefKey) ?? [];
    return raw.map((s) {
      try {
        return OfflineQueueItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<OfflineQueueItem>().toList();
  }

  Future<void> _save(List<OfflineQueueItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefKey,
      items.map((i) => jsonEncode(i.toJson())).toList(),
    );
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<int> pendingCount() async => (await _load()).length;

  /// Called by [OfflineInterceptor] when a mutation fails due to no connection.
  Future<void> enqueue(RequestOptions req) async {
    final path = req.path;
    if (_skipPaths.any((s) => path.startsWith(s))) return;

    final items = await _load();
    items.add(OfflineQueueItem(
      id:        const Uuid().v4(),
      method:    req.method,
      path:      path,
      data:      req.data,
      timestamp: DateTime.now(),
    ));
    await _save(items);
    debugPrint('[OfflineQueue] queued ${req.method} $path  (total: ${items.length})');
  }

  /// Replay all queued items. Returns the number successfully replayed.
  /// Items that still fail increment their retry counter; after [_maxRetries]
  /// they are dropped to avoid stale data building up indefinitely.
  Future<int> drain(Dio apiDio) async {
    final items = await _load();
    if (items.isEmpty) return 0;

    int replayed = 0;
    final remaining = <OfflineQueueItem>[];

    for (final item in items) {
      try {
        final res = await apiDio.request<dynamic>(
          item.path,
          data: item.data,
          options: Options(method: item.method,
              extra: kBackgroundOptions.extra),
        );
        replayed++;
        debugPrint('[OfflineQueue] replayed ${item.method} ${item.path}');
        await _handleSyncResponse(item, res.data);
      } catch (e) {
        final next = item.copyWith(retries: item.retries + 1);
        if (next.retries < _maxRetries) {
          remaining.add(next);
        } else {
          debugPrint('[OfflineQueue] dropped after $_maxRetries retries: ${item.path}');
        }
      }
    }

    await _save(remaining);
    return replayed;
  }

  /// Met à jour le SQLite local après une sync réussie.
  Future<void> _handleSyncResponse(OfflineQueueItem item, dynamic responseData) async {
    if (responseData is! Map) return;

    // Vente créée offline → marquer comme synchronisée
    if (item.method == 'POST' && item.path == '/api/sales/') {
      final clientId  = (item.data is Map) ? item.data['client_id'] as String? : null;
      final reference = responseData['reference'] as String?;
      if (clientId != null && reference != null) {
        await LocalDbService.instance.markSaleSynced(clientId, reference);
        debugPrint('[OfflineQueue] sale $clientId synced → $reference');
      }
    }

    // Client créé offline → marquer comme synchronisé
    if (item.method == 'POST' && item.path == '/api/customers/') {
      final localId  = (item.data is Map) ? item.data['local_id'] as String? : null;
      final serverId = responseData['id'] as String?;
      if (localId != null && serverId != null) {
        await LocalDbService.instance.markCustomerSynced(localId, serverId);
        debugPrint('[OfflineQueue] customer $localId synced → $serverId');
      }
    }

    // Achat créé offline → marquer comme synchronisé
    if (item.method == 'POST' && item.path == '/api/purchases/') {
      final clientId  = (item.data is Map) ? item.data['client_id'] as String? : null;
      final reference = responseData['reference'] as String?;
      if (clientId != null && reference != null) {
        await LocalDbService.instance.markPurchaseSynced(clientId, reference);
        debugPrint('[OfflineQueue] purchase $clientId synced → $reference');
      }
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
