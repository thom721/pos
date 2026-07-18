import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/models/user_model.dart';
import 'package:pos_connect/data/repositories/auth_repository.dart';
import 'package:pos_connect/services/license_service.dart';
import 'package:pos_connect/services/local_db_service.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final UserModel? user;
  final String? error;
  final Map<String, dynamic>? planWarning;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = true,
    this.user,
    this.error,
    this.planWarning,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserModel? user,
    String? error,
    Map<String, dynamic>? planWarning,
    bool clearPlanWarning = false,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        user: user ?? this.user,
        error: error,
        planWarning: clearPlanWarning ? null : (planWarning ?? this.planWarning),
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final token = await _repo.getToken();
    if (token != null && !_isTokenExpired(token)) {
      final userData = await _repo.getSavedUser();
      final warning  = _refreshWarning(await _repo.getSavedPlanWarning());
      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        user: userData != null ? UserModel.fromJson(userData) : null,
        planWarning: warning,
      );
    } else {
      // Token absent ou expiré — forcer un nouveau login
      if (token != null) await _repo.logout();
      state = const AuthState(isAuthenticated: false, isLoading: false);
    }
  }

  /// Décode le payload JWT (sans vérification de signature) pour lire l'expiry.
  static bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = utf8.decode(
          base64Url.decode(base64Url.normalize(parts[1])));
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final exp = data['exp'] as int?;
      if (exp == null) return false;
      return DateTime.now().millisecondsSinceEpoch > exp * 1000;
    } catch (_) {
      return true; // token corrompu → forcer re-login propre
    }
  }

  /// Recalcule days_left à partir de expires_at pour éviter la valeur figée du cache.
  Map<String, dynamic>? _refreshWarning(Map<String, dynamic>? warning) {
    if (warning == null) return null;
    final raw = warning['expires_at']?.toString();
    if (raw == null) return warning;
    final expiresAt = DateTime.tryParse(raw)?.toLocal();
    if (expiresAt == null) return warning;
    final daysLeft = expiresAt.difference(DateTime.now()).inDays;
    if (daysLeft < 0) return null; // expiré → le backend suspendra au prochain login
    return {...warning, 'days_left': daysLeft};
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final token = await _repo.login(username, password);
      await _repo.saveToken(token.accessToken);
      if (token.user != null) await _repo.saveUser(token.user!);
      await _repo.savePlanWarning(token.planWarning);
      await _repo.setConnectionMode('local');

      final user = token.user != null ? UserModel.fromJson(token.user!) : null;
      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        user: user,
        planWarning: token.planWarning,
      );
      return true;
    } catch (e) {
      final msg = _loginErrorMsg(e);
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> cloudLogin(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    final emailLower = email.trim().toLowerCase();

    // ── 1. Vérification locale des credentials (préparation mode hors ligne) ──
    // Ne retourne PAS ici — on essaie toujours l'API cloud pour obtenir un token.
    bool offlineCredOk = false;
    Map<String, dynamic>? offlineUserJson;
    if (!kIsWeb) {
      try {
        final localUser = await LocalDbService.instance.getLocalUser(emailLower);
        if (localUser != null) {
          final hash = await _hashPassword(emailLower, password);
          if (localUser['password_hash'] == hash) {
            offlineCredOk = true;
            offlineUserJson =
                jsonDecode(localUser['user_data'] as String) as Map<String, dynamic>;
          }
        }
      } catch (_) {}
    }

    // ── 2. Essai API cloud — toujours, pour obtenir un token JWT frais ────────
    try {
      final token = await _repo.cloudLogin(email.trim(), password);
      final user = token.user != null ? UserModel.fromJson(token.user!) : null;

      // Sur web, seul l'admin peut accéder à l'interface de gestion cloud.
      if (kIsWeb && (user == null || !user.isAdmin)) {
        await _repo.logout();
        state = state.copyWith(
          isLoading: false,
          error: 'Accès refusé. Seul le propriétaire (admin) peut se connecter via le cloud.',
        );
        return false;
      }

      await _repo.saveToken(token.accessToken);
      if (token.user != null) {
        await _repo.saveUser(token.user!);
        // Mettre à jour le cache hors ligne avec le token frais
        if (!kIsWeb) {
          final hash = await _hashPassword(emailLower, password);
          await LocalDbService.instance.saveLocalUser(
              emailLower, hash, jsonEncode(token.user!));
        }
      }
      await _repo.savePlanWarning(token.planWarning);
      await _repo.setConnectionMode('cloud');

      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        user: user,
        planWarning: token.planWarning,
      );
      return true;
    } catch (e) {
      // ── Réseau inaccessible : utiliser les credentials locaux si disponibles ─
      if (!kIsWeb && _isNetworkError(e)) {
        if (offlineCredOk && offlineUserJson != null) {
          final user = UserModel.fromJson(offlineUserJson);
          await _repo.saveUser(offlineUserJson);
          await _repo.setConnectionMode('cloud');
          state = AuthState(isAuthenticated: true, isLoading: false, user: user);
          return true;
        }
        state = state.copyWith(
          isLoading: false,
          error: 'Pas de connexion. Connectez-vous une première fois avec internet pour accéder hors ligne.',
        );
        return false;
      }

      String msg;
      if (e.toString().contains('401') || e.toString().contains('400')) {
        msg = 'Email ou mot de passe incorrect';
      } else if (e.toString().contains('403')) {
        msg = 'Abonnement suspendu ou expiré';
      } else if (e.toString().contains('409')) {
        msg = 'Limite de caisses atteinte. Fermez une caisse avant de vous connecter.';
      } else {
        msg = 'Impossible de se connecter au cloud. Vérifiez votre connexion.';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  static Future<String> _hashPassword(String email, String password) async {
    final sha = Sha256();
    final hash = await sha.hash(utf8.encode('$email:$password'));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _isNetworkError(Object e) =>
      e is SocketException ||
      (e is DioException &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.unknown));

  String _loginErrorMsg(Object e) {
    final s = e.toString();
    if (s.contains('401') || s.contains('400')) return 'Identifiants incorrects';
    if (s.contains('receive timeout') || s.contains('receiveTimeout')) {
      return 'Le serveur ne répond pas (base de données lente ou non démarrée). Réessayez dans quelques secondes.';
    }
    if (s.contains('connect timeout') || s.contains('connectTimeout') ||
        s.contains('connection')) {
      return 'Impossible de joindre le serveur. Vérifiez l\'adresse IP et que le serveur est démarré.';
    }
    return 'Impossible de se connecter. Vérifiez votre connexion.';
  }

  void dismissPlanWarning() {
    // Cache uniquement l'état "masqué pour cette session" — on garde expires_at
    // pour que le décompte reste correct au prochain démarrage.
    state = state.copyWith(clearPlanWarning: true);
  }

  void clearMustChangePassword() {
    final user = state.user;
    if (user == null) return;
    final updated = UserModel.fromJson({
      ...user.toJson(),
      'must_change_password': false,
    });
    state = state.copyWith(user: updated);
  }

  /// Déconnexion explicite (bouton "Déconnexion") — efface tout le cache.
  Future<void> logout() async {
    await _repo.logout(explicit: true);
    await LicenseService.clearCache();
    state = const AuthState(isAuthenticated: false, isLoading: false);
  }

  /// Déconnexion automatique suite à un 401 sur une requête utilisateur.
  /// Conserve userKey pour permettre la reprise offline.
  Future<void> logoutDueToExpiry() async {
    await _repo.logout(explicit: false);
    state = const AuthState(isAuthenticated: false, isLoading: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(AuthRepository());
});

/// Reads the saved tenant JSON from SharedPreferences.
/// Returns null in local mode (no tenant saved).
final tenantProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(authProvider); // rebuild when auth state changes
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(AppConstants.tenantKey);
  if (raw == null) return null;
  return jsonDecode(raw) as Map<String, dynamic>;
});
