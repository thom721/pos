import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/local_https.dart';
import 'package:pos_connect/services/offline_queue_service.dart';

const _localBaseUrl = 'https://infini-post.local';

final _unauthorizedCtrl = StreamController<void>.broadcast();
Stream<void> get onUnauthorized => _unauthorizedCtrl.stream;

Future<String?> _readToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(AppConstants.tokenKey);
}

Future<void> _deleteToken() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(AppConstants.tokenKey);
}

Future<String> getEffectiveBaseUrl() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(AppConstants.serverUrlKey);
  return (saved != null && saved.isNotEmpty) ? saved : AppConstants.baseUrl;
}

Future<void> initServerUrl() async {
  // Android is cloud-only: ignore any saved local server URL, always use cloud
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    dio.options.baseUrl = AppConstants.cloudUrl;
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final url = prefs.getString(AppConstants.serverUrlKey);
  if (url == _localBaseUrl) {
    final ip = prefs.getString(AppConstants.serverIpKey) ?? '';
    if (ip.isNotEmpty) {
      dio.options.baseUrl = _localBaseUrl;
      configureLocalHttps(dio, ip);
      return;
    }
  }
  dio.options.baseUrl =
      (url != null && url.isNotEmpty) ? url : AppConstants.baseUrl;
}

/// Sauvegarde l'IP du serveur local et configure l'adaptateur HTTPS interne.
/// L'URL effective est toujours https://infini-post.local —
/// la résolution DNS vers l'IP se fait au niveau socket dans Dart,
/// aucune modification du fichier hosts requise sur les postes clients.
Future<void> saveLocalServer(String ip) async {
  final prefs = await SharedPreferences.getInstance();
  final trimmed = ip.trim();
  if (trimmed.isEmpty) {
    await prefs.remove(AppConstants.serverIpKey);
    await prefs.remove(AppConstants.serverUrlKey);
    dio.options.baseUrl = AppConstants.baseUrl;
    resetLocalHttps(dio);
  } else {
    await prefs.setString(AppConstants.serverIpKey, trimmed);
    await prefs.setString(AppConstants.serverUrlKey, _localBaseUrl);
    dio.options.baseUrl = _localBaseUrl;
    configureLocalHttps(dio, trimmed);
  }
}

Future<void> saveServerUrl(String url) async {
  final prefs = await SharedPreferences.getInstance();
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    await prefs.remove(AppConstants.serverUrlKey);
    dio.options.baseUrl = AppConstants.baseUrl;
  } else {
    await prefs.setString(AppConstants.serverUrlKey, trimmed);
    dio.options.baseUrl = trimmed;
  }
}

Dio createDio() {
  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    contentType: 'application/json',
  ));

  dio.interceptors.add(AuthInterceptor(dio));
  dio.interceptors.add(OfflineInterceptor());
  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
    error: true,
    logPrint: (obj) => debugPrint(obj.toString()),
  ));

  return dio;
}

class AuthInterceptor extends Interceptor {
  final Dio dio;

  AuthInterceptor(this.dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _readToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      await _deleteToken();
      _unauthorizedCtrl.add(null);
    }
    handler.next(err);
  }
}

// ── Offline interceptor ───────────────────────────────────────────────────────

class OfflineInterceptor extends Interceptor {
  static bool _isMutation(String method) =>
      const {'POST', 'PUT', 'PATCH', 'DELETE'}.contains(method.toUpperCase());

  static bool _isConnectionError(DioException err) =>
      err.type == DioExceptionType.connectionError ||
      err.type == DioExceptionType.connectionTimeout ||
      err.type == DioExceptionType.unknown;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_isConnectionError(err) && _isMutation(err.requestOptions.method)) {
      await OfflineQueueService.instance.enqueue(err.requestOptions);
    }
    handler.next(err);
  }
}

// ── Singleton Dio instance ────────────────────────────────────────────────────

final dio = createDio();

// Helper to extract error message
String extractErrorMessage(DioException e) {
  try {
    final data = e.response?.data;
    if (data is Map) {
      return data['detail']?.toString() ??
          data['message']?.toString() ??
          'Erreur inconnue';
    }
    return e.message ?? 'Erreur de connexion';
  } catch (_) {
    return 'Erreur de connexion';
  }
}
