import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';

const _secure = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Jeton d'authentification — Keychain (via FlutterSecureStorage) avec repli
/// SharedPreferences. Le repli existe pour macOS ad-hoc (signature sans
/// identité d'équipe stable, voir CIAdhoc.entitlements) : le Keychain y
/// refuse TOUTE écriture avec PlatformException -34018
/// (errSecMissingEntitlement), même hors sandbox — confirmé en réel sur le
/// build v2.0.75. Moins "sécurisé" qu'un vrai Keychain, mais fonctionnel ;
/// redevient transparent une fois un vrai certificat Developer ID en place.
Future<void> saveAuthToken(String token) async {
  try {
    await _secure.write(key: AppConstants.tokenKey, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
  } catch (_) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.tokenKey, token);
  }
}

Future<String?> readAuthTokenStorage() async {
  try {
    final v = await _secure.read(key: AppConstants.tokenKey);
    if (v != null) return v;
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(AppConstants.tokenKey);
}

Future<void> deleteAuthToken() async {
  try {
    await _secure.delete(key: AppConstants.tokenKey);
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(AppConstants.tokenKey);
}
