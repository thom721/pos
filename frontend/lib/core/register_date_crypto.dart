import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Signe une date ISO avec HMAC-SHA256(device_id).
/// Format stocké: "<isoDate>.<base64url_hmac>"
/// Retourne null si la date est nulle.
Future<String?> signDate(String? isoDate, String deviceId) async {
  if (isoDate == null) return null;
  final hmac = Hmac.sha256();
  final key  = SecretKey(utf8.encode(deviceId));
  final mac  = await hmac.calculateMac(utf8.encode(isoDate), secretKey: key);
  final sig  = base64Url.encode(mac.bytes);
  return '$isoDate.$sig';
}

/// Vérifie et extrait la date ISO depuis un token signé.
/// Retourne null si le token est absent, malformé, ou si le HMAC ne correspond pas.
Future<String?> verifyDate(String? token, String deviceId) async {
  if (token == null) return null;
  final dot = token.lastIndexOf('.');
  if (dot < 1) return null;
  final isoDate = token.substring(0, dot);
  final storedSig = token.substring(dot + 1);

  final hmac = Hmac.sha256();
  final key  = SecretKey(utf8.encode(deviceId));
  final mac  = await hmac.calculateMac(utf8.encode(isoDate), secretKey: key);
  final expectedSig = base64Url.encode(mac.bytes);

  if (storedSig != expectedSig) return null;  // tampering détecté
  return isoDate;
}
