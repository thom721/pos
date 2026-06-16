import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/models/user_model.dart';
import 'package:pos_connect/data/repositories/auth_repository.dart';
import 'package:pos_connect/services/license_service.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final UserModel? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = true,
    this.user,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserModel? user,
    String? error,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        user: user ?? this.user,
        error: error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final token = await _repo.getToken();
    if (token != null) {
      final userData = await _repo.getSavedUser();
      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        user: userData != null ? UserModel.fromJson(userData) : null,
      );
    } else {
      state = const AuthState(isAuthenticated: false, isLoading: false);
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final token = await _repo.login(username, password);
      await _repo.saveToken(token.accessToken);
      if (token.user != null) await _repo.saveUser(token.user!);
      await _repo.setConnectionMode('local');

      final user = token.user != null ? UserModel.fromJson(token.user!) : null;
      state = AuthState(isAuthenticated: true, isLoading: false, user: user);
      return true;
    } catch (e) {
      final msg = e.toString().contains('401')
          ? 'Identifiants incorrects'
          : 'Impossible de se connecter. Vérifiez votre connexion.';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> cloudLogin(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final token = await _repo.cloudLogin(email, password);

      final user = token.user != null ? UserModel.fromJson(token.user!) : null;

      // Only admin/owner accounts can log in via cloud
      if (user == null || !user.isAdmin) {
        await _repo.logout();
        state = state.copyWith(
          isLoading: false,
          error: 'Accès refusé. Seul le propriétaire (admin) peut se connecter via le cloud.',
        );
        return false;
      }

      await _repo.saveToken(token.accessToken);
      if (token.user != null) await _repo.saveUser(token.user!);
      await _repo.setConnectionMode('cloud');

      state = AuthState(isAuthenticated: true, isLoading: false, user: user);
      return true;
    } catch (e) {
      String msg;
      if (e.toString().contains('401') || e.toString().contains('400')) {
        msg = 'Email ou mot de passe incorrect';
      } else if (e.toString().contains('403')) {
        msg = 'Abonnement suspendu ou expiré';
      } else {
        msg = 'Impossible de se connecter au cloud. Vérifiez votre connexion.';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
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

  Future<void> logout() async {
    await _repo.logout();
    await LicenseService.clearCache();
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
