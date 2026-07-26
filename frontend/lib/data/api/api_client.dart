import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/local_https.dart';
import 'package:pos_connect/services/offline_queue_service.dart';

const _localBaseUrl = 'https://infini-post.local';

final _unauthorizedCtrl = StreamController<String?>.broadcast();
Stream<String?> get onUnauthorized => _unauthorizedCtrl.stream;

const _tokenStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

Future<String?> _readToken() async {
  // Migration one-shot depuis SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final legacy = prefs.getString(AppConstants.tokenKey);
  if (legacy != null) {
    await _tokenStorage.write(key: AppConstants.tokenKey, value: legacy);
    await prefs.remove(AppConstants.tokenKey);
  }
  return _tokenStorage.read(key: AppConstants.tokenKey);
}

Future<void> _deleteToken() async {
  await _tokenStorage.delete(key: AppConstants.tokenKey);
  // Nettoyage legacy au cas où
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(AppConstants.tokenKey);
}

Future<String> getEffectiveBaseUrl() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(AppConstants.serverUrlKey);
  return (saved != null && saved.isNotEmpty) ? saved : AppConstants.baseUrl;
}

Future<void> initServerUrl() async {
  // Web release: app is served by FastAPI itself → origin IS the API server.
  // Web debug: Flutter dev server ≠ FastAPI → use compiled AppConstants.baseUrl.
  if (kIsWeb) {
    dio.options.baseUrl = kReleaseMode ? Uri.base.origin : AppConstants.baseUrl;
    return;
  }
  // Android is cloud-only: ignore any saved local server URL, always use cloud
  if (defaultTargetPlatform == TargetPlatform.android) {
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
  // Web release: utilise Uri.base.origin dès la création (avant même initServerUrl).
  // Web debug / natif: AppConstants.baseUrl (127.0.0.1:9003 par défaut en dev).
  final initialBaseUrl =
      (kIsWeb && kReleaseMode) ? Uri.base.origin : AppConstants.baseUrl;
  final dio = Dio(BaseOptions(
    baseUrl: initialBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    contentType: 'application/json',
  ));

  dio.interceptors.add(AuthInterceptor(dio));
  dio.interceptors.add(OfflineInterceptor());
  if (!kReleaseMode) {
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => debugPrint(obj.toString()),
    ));
  }

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
      // Background requests (sync, heartbeat, cache) carry this flag — skip
      // auto-logout so a stale sync token doesn't disconnect the active user.
      final skipLogout = err.requestOptions.extra['skipAutoLogout'] == true;
      if (!skipLogout) {
        await _deleteToken();
        final detail = _extractDetail(err);
        _unauthorizedCtrl.add(detail);
      }
    }
    handler.next(err);
  }
}

String? _extractDetail(DioException err) {
  try {
    final data = err.response?.data;
    if (data is Map) {
      return data['detail']?.toString() ?? data['message']?.toString();
    }
  } catch (_) {}
  return null;
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
    final skip = err.requestOptions.extra['skipOfflineQueue'] == true;
    if (!skip && _isConnectionError(err) && _isMutation(err.requestOptions.method)) {
      await OfflineQueueService.instance.enqueue(err.requestOptions);
    }
    handler.next(err);
  }
}

// ── Singleton Dio instance ────────────────────────────────────────────────────

final dio = createDio();

/// Options to pass to background API calls (sync, heartbeat, cache).
/// A 401 on these requests will NOT trigger auto-logout — the user keeps
/// their session and the error is silently discarded.
final kBackgroundOptions = Options(extra: {'skipAutoLogout': true});

/// Traduit une DioException en message lisible pour l'utilisateur.
/// Priorité : code HTTP connu → message de l'API → fallback générique.
// HTTP status phrases that are too generic to show as-is.
const _kGenericPhrases = {
  'Internal Server Error', 'Bad Request', 'Unprocessable Entity',
  'Not Found', 'Forbidden', 'Unauthorized', 'Service Unavailable',
};

String extractErrorMessage(DioException e) {
  final status = e.response?.statusCode;

  // 1. Priorité : message spécifique retourné par le serveur.
  try {
    final data = e.response?.data;
    if (data is Map) {
      final raw = (data['detail'] ?? data['message'])?.toString();
      if (raw != null && raw.isNotEmpty && !_kGenericPhrases.contains(raw)) {
        return raw;
      }
    }
  } catch (_) {}

  // 2. Fallback par code HTTP — messages français clairs.
  if (status == 400) return 'Requête invalide — vérifiez les données saisies.';
  if (status == 401) return 'Session expirée. Veuillez vous reconnecter.';
  if (status == 403) return 'Vous n\'avez pas la permission d\'effectuer cette action.';
  if (status == 404) return 'Ressource introuvable.';
  if (status == 409) return 'Ce contenu existe déjà.';
  if (status == 422) return 'Données invalides — vérifiez les informations saisies.';
  if (status == 500) return 'Erreur interne du serveur. Contactez l\'administrateur.';
  if (status == 503) return 'Service temporairement indisponible.';
  if (status != null) return 'Erreur serveur ($status).';

  // 3. Erreurs réseau.
  final t = e.type;
  if (t == DioExceptionType.connectionError ||
      t == DioExceptionType.unknown) {
    return 'Impossible de joindre le serveur — vérifiez votre connexion.';
  }
  if (t == DioExceptionType.connectionTimeout ||
      t == DioExceptionType.sendTimeout ||
      t == DioExceptionType.receiveTimeout) {
    return 'Le serveur met trop de temps à répondre.';
  }

  return 'Erreur de connexion.';
}

/// Traduit n'importe quelle exception (DioException ou autre) en message lisible.
String extractAnyError(Object e) {
  if (e is DioException) return extractErrorMessage(e);
  if (e is Exception) {
    final raw = e.toString();
    // Strip "Exception: " prefix Flutter/Dart adds automatically
    final msg = raw.startsWith('Exception: ') ? raw.substring(11) : raw;
    if (msg.isNotEmpty) return msg;
  }
  return 'Une erreur inattendue s\'est produite.';
}
