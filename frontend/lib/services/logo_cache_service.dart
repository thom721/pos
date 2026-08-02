import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_connect/data/api/api_client.dart';

const _kLogoCacheUrlKey = 'logo_cache_url';
const _kLogoCacheBytesKey = 'logo_cache_bytes';

/// Cache local du logo de l'entreprise — évite de re-télécharger l'image à
/// chaque impression de reçu (PDF, Bluetooth) et permet de l'afficher même
/// hors ligne. Rafraîchi silencieusement dès qu'un téléchargement réussit ;
/// se rabat sur la dernière version connue si le réseau est indisponible.
class LogoCacheService {
  LogoCacheService._();
  static final LogoCacheService instance = LogoCacheService._();

  /// Retourne les octets du logo pour [logoPath] : tente un téléchargement
  /// live (et met à jour le cache en cas de succès), sinon renvoie la
  /// dernière version mise en cache pour CE MÊME chemin (null si aucune ou
  /// si le logo a changé depuis).
  Future<Uint8List?> getLogoBytes(String logoPath) async {
    if (logoPath.isEmpty) return null;

    try {
      final res = await dio
          .get(logoPath, options: Options(responseType: ResponseType.bytes))
          .timeout(const Duration(seconds: 5));
      final bytes = Uint8List.fromList(res.data as List<int>);
      _cache(logoPath, bytes); // best-effort, ne bloque pas le retour
      return bytes;
    } catch (_) {
      return _readCache(logoPath);
    }
  }

  Future<void> _cache(String logoPath, Uint8List bytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLogoCacheUrlKey, logoPath);
      await prefs.setString(_kLogoCacheBytesKey, base64Encode(bytes));
    } catch (_) {}
  }

  Future<Uint8List?> _readCache(String logoPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kLogoCacheUrlKey) != logoPath) return null;
      final raw = prefs.getString(_kLogoCacheBytesKey);
      if (raw == null) return null;
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }
}
