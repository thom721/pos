import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/user_model.dart';

class AuthRepository {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ── Device ID ───────────────────────────────────────────────────────────

  Future<String> getOrCreateDeviceId() async {
    final prefs = await _prefs;
    var id = prefs.getString(AppConstants.deviceIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(AppConstants.deviceIdKey, id);
    }
    return id;
  }

  // ── Connection mode ─────────────────────────────────────────────────────

  Future<String> getConnectionMode() async {
    final prefs = await _prefs;
    return prefs.getString(AppConstants.connectionModeKey) ?? 'local';
  }

  Future<void> setConnectionMode(String mode) async {
    final prefs = await _prefs;
    await prefs.setString(AppConstants.connectionModeKey, mode);
  }

  // ── Local login (username + password → OAuth2 form) ─────────────────────

  Future<AuthToken> login(String username, String password) async {
    final response = await dio.post(
      '/api/auth/login',
      data: FormData.fromMap({'username': username, 'password': password}),
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    return AuthToken.fromJson(response.data);
  }

  // ── Cloud login (email + password → JSON) ───────────────────────────────

  Future<AuthToken> cloudLogin(String email, String password) async {
    final deviceId = await getOrCreateDeviceId();

    final response = await dio.post('/api/public/login', data: {
      'email': email,
      'password': password,
      'device_id': deviceId,
    });

    final token = AuthToken.fromJson(response.data);

    // Save tenant info
    if (response.data['tenant'] != null) {
      final prefs = await _prefs;
      await prefs.setString(
          AppConstants.tenantKey, jsonEncode(response.data['tenant']));
    }

    return token;
  }

  // ── Registration (cloud only) ───────────────────────────────────────────

  Future<Map<String, dynamic>> register({
    required String businessName,
    required String email,
    required String password,
    String? phone,
  }) async {
    final response = await dio.post('/api/public/register', data: {
      'business_name': businessName,
      'owner_email': email,
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });

    return response.data as Map<String, dynamic>;
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  Future<void> saveToken(String token) async {
    final prefs = await _prefs;
    await prefs.setString(AppConstants.tokenKey, token);
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await _prefs;
    await prefs.setString(AppConstants.userKey, jsonEncode(user));
  }

  Future<String?> getToken() async {
    final prefs = await _prefs;
    return prefs.getString(AppConstants.tokenKey);
  }

  Future<Map<String, dynamic>?> getSavedUser() async {
    final prefs = await _prefs;
    final raw = prefs.getString(AppConstants.userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> savePlanWarning(Map<String, dynamic>? warning) async {
    final prefs = await _prefs;
    if (warning == null) {
      await prefs.remove(AppConstants.planWarningKey);
    } else {
      await prefs.setString(AppConstants.planWarningKey, jsonEncode(warning));
    }
  }

  Future<Map<String, dynamic>?> getSavedPlanWarning() async {
    final prefs = await _prefs;
    final raw = prefs.getString(AppConstants.planWarningKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> logout() async {
    final prefs = await _prefs;
    // Tell the server to free the register slot before clearing the local token,
    // so the next device can log in immediately without waiting for the 5-min heartbeat timeout.
    final deviceId = prefs.getString(AppConstants.deviceIdKey);
    if (deviceId != null) {
      try {
        await dio.post(
          '/api/warehouses/registers/logout',
          data: {'device_id': deviceId},
        );
      } catch (_) {
        // Best-effort — slot will expire via heartbeat timeout if offline
      }
    }
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);
    await prefs.remove(AppConstants.tenantKey);
    await prefs.remove(AppConstants.connectionModeKey);
    await prefs.remove(AppConstants.planWarningKey);
  }
}
