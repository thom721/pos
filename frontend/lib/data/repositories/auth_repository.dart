import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/api/token_storage.dart';
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
    // FormData.fromMap() force TOUJOURS un encodage multipart/form-data,
    // quel que soit le contentType déclaré ici — le corps réel ne
    // correspondait donc jamais au Content-Type annoncé
    // (application/x-www-form-urlencoded), et le serveur (qui attend un
    // OAuth2PasswordRequestForm classique) échouait à le parser : 400 Bad
    // Request systématique, quels que soient les identifiants saisis. Un
    // Map simple laisse Dio l'encoder correctement en url-encoded.
    final response = await dio.post(
      '/api/auth/login',
      data: {'username': username, 'password': password},
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        extra: {'skipAutoLogout': true}, // 401 = mauvais identifiants, pas session expirée
      ),
    );
    return AuthToken.fromJson(response.data);
  }

  // ── Cloud login (email + password → JSON) ───────────────────────────────

  Future<AuthToken> cloudLogin(String email, String password) async {
    // Web : jamais de device_id au login — sinon le simple fait d'ouvrir le
    // tableau de bord dans un navigateur réclame silencieusement la caisse
    // principale du tenant (device_id posé + "Appareil en attente" affiché
    // alors qu'aucun vrai appareil ne s'est jamais connecté). Le backend
    // gère déjà ce cas ("admin web sans caisse liée → pas de vérification",
    // voir api/core/tenant.py::require_active_plan). Ouvrir une session
    // caisse depuis le web reste possible : pos_screen.dart récupère son
    // propre device_id séparément, au moment voulu, pas ici.
    final deviceId = kIsWeb ? null : await getOrCreateDeviceId();

    final response = await dio.post('/api/public/login',
      data: {
        'email': email,
        'password': password,
        if (deviceId != null) 'device_id': deviceId,
      },
      options: Options(extra: {'skipAutoLogout': true}), // idem
    );

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
    String? referralCode,
  }) async {
    final response = await dio.post('/api/public/register', data: {
      'business_name': businessName,
      'owner_email': email,
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (referralCode != null && referralCode.isNotEmpty) 'referral_code': referralCode,
    });

    return response.data as Map<String, dynamic>;
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  Future<void> saveToken(String token) async {
    await saveAuthToken(token);
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await _prefs;
    await prefs.setString(AppConstants.userKey, jsonEncode(user));
  }

  Future<String?> getToken() async {
    return readAuthTokenStorage();
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

  /// [explicit] = true  → user pressed "Déconnexion" in the menu: clear all cache.
  /// [explicit] = false → automatic logout due to token expiry / 401: preserve
  ///   the cached user so the offline recovery flow can restore the session.
  Future<void> logout({bool explicit = true}) async {
    final prefs = await _prefs;
    // Free the register slot on the server before clearing the local token.
    final deviceId = prefs.getString(AppConstants.deviceIdKey);
    final token    = await readAuthTokenStorage();
    if (explicit && deviceId != null && token != null) {
      try {
        await dio.post(
          '/api/warehouses/registers/logout',
          data: {'device_id': deviceId},
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            validateStatus: (_) => true,
          ),
        );
      } catch (_) {}
    }
    await deleteAuthToken();
    // Keep userKey + tenantKey for offline session recovery on non-explicit logouts
    if (explicit) {
      await prefs.remove(AppConstants.userKey);
      await prefs.remove(AppConstants.tenantKey);
      await prefs.remove(AppConstants.planWarningKey);
      await prefs.remove('pos_caisse_session');
    }
    // connectionModeKey décrit la CONFIGURATION DE CE POSTE (cloud direct vs
    // serveur local, choisie dans l'assistant d'installation) — pas l'état
    // d'une session. Au même titre que serverUrlKey/serverIpKey (jamais
    // supprimés ici non plus), elle doit survivre à une déconnexion. Sans
    // ça, un poste bureau configuré en cloud direct retombait sur le
    // formulaire "serveur local" (et tentait https://infini-post.local,
    // qui échoue toujours avec une vraie erreur de certificat) dès la
    // première reconnexion.
  }

  /// Supprime toutes les clés SharedPreferences liées à un tenant.
  /// Conserve uniquement les données d'appareil/plateforme.
  /// Appelé au login quand un tenant différent du précédent est détecté.
  static const _platformKeys = {
    AppConstants.deviceIdKey,
    AppConstants.serverUrlKey,
    AppConstants.serverIpKey,
    AppConstants.clientSetupDoneKey,
    AppConstants.connectionModeKey,
    'device_paper_width',
    'device_receipt_darkness',
    'device_bt_mac',
    'device_bt_name',
    'device_pos_auto_print',
  };

  static Future<void> clearTenantData(SharedPreferences prefs) async {
    final toRemove = prefs.getKeys()
        .where((k) => !_platformKeys.contains(k))
        .toList();
    for (final key in toRemove) {
      await prefs.remove(key);
    }
  }
}
