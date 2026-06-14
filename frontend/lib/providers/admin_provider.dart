import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:pos_connect/core/constants.dart';

const _kAdminTokenKey = 'superadmin_token';

// ── Standalone Dio builder (no AuthInterceptor, no dependency on global dio) ──

Dio _buildAdminDio({required String baseUrl, String token = ''}) {
  return Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    contentType: 'application/json',
    headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
  ));
}

Future<String> _resolveBaseUrl() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(AppConstants.serverUrlKey);
  return (saved != null && saved.isNotEmpty) ? saved : AppConstants.baseUrl;
}

// ── State ─────────────────────────────────────────────────────────────────────

class AdminState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;

  const AdminState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
  });

  AdminState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
  }) =>
      AdminState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class AdminNotifier extends StateNotifier<AdminState> {
  AdminNotifier() : super(const AdminState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kAdminTokenKey) != null) {
      state = state.copyWith(isAuthenticated: true);
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final baseUrl = await _resolveBaseUrl();
      final tempDio = _buildAdminDio(baseUrl: baseUrl);
      final res = await tempDio.post(
        '/api/admin/auth',
        data: {'email': email, 'password': password},
      );
      final token = res.data['access_token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAdminTokenKey, token);
      state = state.copyWith(isAuthenticated: true, isLoading: false);
      return true;
    } on DioException catch (e) {
      final msg = e.response?.statusCode == 403
          ? 'Email ou mot de passe invalide'
          : 'Impossible de joindre le serveur. Vérifiez l\'adresse.';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Erreur inattendue');
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAdminTokenKey);
    state = const AdminState();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final adminProvider =
    StateNotifierProvider<AdminNotifier, AdminState>((ref) => AdminNotifier());

/// Authenticated Dio for admin API calls — completely independent of user session.
final adminDioProvider = FutureProvider<Dio>((ref) async {
  ref.watch(adminProvider); // rebuild when auth state changes
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(_kAdminTokenKey) ?? '';
  final baseUrl = await _resolveBaseUrl();
  return _buildAdminDio(baseUrl: baseUrl, token: token);
});
