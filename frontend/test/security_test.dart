import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/repositories/auth_repository.dart';
import 'package:pos_connect/providers/auth_provider.dart';

void main() {
  // ── Test 1 : Migration SharedPreferences → FlutterSecureStorage ──────────────

  group('Token migration (FIX 1)', () {
    setUp(() {
      // Démarrer avec FlutterSecureStorage vide et un token legacy dans SharedPreferences
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        AppConstants.tokenKey: 'legacy_jwt_token',
      });
    });

    test('saveToken écrit dans FlutterSecureStorage et nettoie SharedPreferences', () async {
      final repo = AuthRepository();

      // Avant la migration : getToken() lit dans SecureStorage → null
      expect(await repo.getToken(), isNull);

      // Simuler l'arrivée d'un nouveau token (post-login)
      await repo.saveToken('new_jwt_token');

      // Le token est maintenant dans SecureStorage
      expect(await repo.getToken(), equals('new_jwt_token'));

      // SharedPreferences ne contient plus le token
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppConstants.tokenKey), isNull);
    });

    test('logout supprime le token de FlutterSecureStorage', () async {
      final repo = AuthRepository();
      await repo.saveToken('some_jwt_token');
      expect(await repo.getToken(), equals('some_jwt_token'));

      await repo.logout(explicit: true);

      expect(await repo.getToken(), isNull);
    });
  });

  // ── Test 2 : _isTokenExpired retourne true sur token corrompu (FIX 12) ────────

  group('_isTokenExpired sur token corrompu (FIX 12)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('token avec payload illisible → AuthNotifier non authentifié après init', () async {
      // Un token JWT en apparence valide (3 parties) mais avec un payload non JSON valide.
      // Les caractères `!` ne sont pas du base64 URL valide → FormatException dans le catch.
      // Après FIX 12, le catch retourne true → re-login forcé.
      const corruptedToken = 'eyJhbGciOiJIUzI1NiJ9.!!!invalid_payload!!!.signature';

      FlutterSecureStorage.setMockInitialValues({
        AppConstants.tokenKey: corruptedToken,
      });

      final repo = AuthRepository();
      final notifier = AuthNotifier(repo);

      // Laisser _init() se terminer (async)
      await Future.delayed(const Duration(milliseconds: 200));

      // Le token corrompu doit forcer l'état non authentifié
      expect(notifier.state.isAuthenticated, isFalse);
      expect(notifier.state.isLoading, isFalse);
    });

    test('token expiré → AuthNotifier non authentifié après init', () async {
      // Token JWT bien formé mais avec exp dans le passé (1970-01-01)
      // Header: {"alg":"HS256","typ":"JWT"}
      // Payload: {"sub":"user1","exp":1}
      // (signature bidon)
      const expiredToken =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJzdWIiOiJ1c2VyMSIsImV4cCI6MX0'
          '.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

      FlutterSecureStorage.setMockInitialValues({
        AppConstants.tokenKey: expiredToken,
      });

      final repo = AuthRepository();
      final notifier = AuthNotifier(repo);

      await Future.delayed(const Duration(milliseconds: 200));

      expect(notifier.state.isAuthenticated, isFalse);
      expect(notifier.state.isLoading, isFalse);
    });
  });
}
