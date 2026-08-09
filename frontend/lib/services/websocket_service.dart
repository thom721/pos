import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/api_client.dart';

typedef SyncCallback = void Function();
typedef ForceLogoutCallback = void Function();

const _tokenStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Maintains a persistent WebSocket connection to the cloud API (Android and
/// desktop — start() no-ops on web, which IOWebSocketChannel doesn't support).
/// The server pushes {"type": "sync"} after every write mutation, triggering
/// an immediate sync + settings/license/billing refresh instead of waiting
/// for the periodic fallback timer.
class WebSocketService {
  WebSocketService._();
  static final WebSocketService instance = WebSocketService._();

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _retrySeconds = 1;
  bool _active = false;
  SyncCallback? _onSync;
  ForceLogoutCallback? _onPermissionsChanged;

  // ── Public API ──────────────────────────────────────────────────────────────

  void start(SyncCallback onSync, {ForceLogoutCallback? onPermissionsChanged}) {
    if (kIsWeb) return;
    _onSync = onSync;
    _onPermissionsChanged = onPermissionsChanged;
    _active = true;
    _retrySeconds = 1;
    _connect();
  }

  void stop() {
    _active = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
    _retrySeconds = 1;
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    if (!_active) return;

    final token = await _tokenStorage.read(key: AppConstants.tokenKey);
    if (token == null) return;

    // Convert the current HTTP(S) base URL to its WebSocket equivalent
    final base = dio.options.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    // Backend expects token as ?token= query param (FastAPI Query dependency)
    final wsUri = Uri.parse('$base/ws?token=$token');

    try {
      _channel = IOWebSocketChannel.connect(wsUri);
      await _channel!.ready; // throws if the handshake fails
      _retrySeconds = 1;
      debugPrint('[WS] connected to $base');

      _channel!.stream.listen(
        _onMessage,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[WS] connect error: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      if (msg['type'] == 'sync') {
        debugPrint('[WS] sync push received');
        _onSync?.call();
      } else if (msg['type'] == 'permissions_changed') {
        debugPrint('[WS] permissions_changed push received');
        _onPermissionsChanged?.call();
      }
      // 'ping' messages are silently ignored
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (!_active) return;
    _channel?.sink.close(); // fermer proprement l'ancien socket
    _channel = null;
    debugPrint('[WS] reconnect in ${_retrySeconds}s');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _retrySeconds), _connect);
    // Exponential backoff: 1 → 2 → 4 → … → 60 s max
    _retrySeconds = (_retrySeconds * 2).clamp(1, 60);
  }
}
