import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';

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
  dio.options.baseUrl = await getEffectiveBaseUrl();
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

// Singleton Dio instance
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
