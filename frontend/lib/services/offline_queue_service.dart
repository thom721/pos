import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
        await apiDio.request<dynamic>(
          item.path,
          data: item.data,
          options: Options(method: item.method),
        );
        replayed++;
        debugPrint('[OfflineQueue] replayed ${item.method} ${item.path}');
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

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
