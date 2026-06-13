import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/user_model.dart';
import 'package:pos_connect/data/repositories/auth_repository.dart';

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
    state = const AuthState(isAuthenticated: false, isLoading: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(AuthRepository());
});
