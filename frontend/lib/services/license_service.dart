import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/api_client.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kDataKey       = 'license_data';
const _kSigKey        = 'license_sig';
const _kOfflineGrace  = 3; // days of grace after valid_until expires

// ── Result type ───────────────────────────────────────────────────────────────

enum LicenseAccess { allowed, warning, blocked }

class LicenseStatus {
  final LicenseAccess access;
  final String status;            // trial | active | expired | suspended | local
  final bool isOffline;
  final int? daysLeft;            // trial or subscription days remaining
  final String? message;          // shown when warning or blocked
  final String tenantType;        // 'shared' | 'selfhosted'
  final String? selfHostedUrl;
  final int maxCaisses;
  final int currentCaisses;
  final bool caisseOverLimit;
  final double pricePerExtraCaisseHtg;
  final double pricePerExtraCaisseUsd;

  const LicenseStatus({
    required this.access,
    required this.status,
    this.isOffline = false,
    this.daysLeft,
    this.message,
    this.tenantType = 'shared',
    this.selfHostedUrl,
    this.maxCaisses = 1,
    this.currentCaisses = 0,
    this.caisseOverLimit = false,
    this.pricePerExtraCaisseHtg = 500.0,
    this.pricePerExtraCaisseUsd = 4.0,
  });

  bool get isAllowed  => access != LicenseAccess.blocked;
  bool get hasWarning => access == LicenseAccess.warning;
}

// ── Service ───────────────────────────────────────────────────────────────────

class LicenseService {
  static const _storage = FlutterSecureStorage();

  // ── Public entry point ─────────────────────────────────────────────────────

  /// Check license. Tries server first, falls back to signed cache.
  static Future<LicenseStatus> check() async {
    final now = DateTime.now().toUtc();

    // 1. Try fresh license
    Map<String, dynamic>? payload = await _fetchAndCache();
    final isOffline = payload == null;

    // 2. Fall back to signed cache
    if (isOffline) payload = await _readCached();

    // 3. No license at all → local mode or first boot
    if (payload == null) {
      return LicenseStatus(
        access: isOffline ? LicenseAccess.warning : LicenseAccess.allowed,
        status: 'local',
        isOffline: isOffline,
        message: isOffline
            ? 'Impossible de vérifier votre licence. Reconnectez-vous à internet.'
            : null,
      );
    }

    final tenantStatus    = payload['status'] as String? ?? 'unknown';
    final tenantType      = payload['tenant_type'] as String? ?? 'shared';
    final selfHostedUrl   = payload['self_hosted_url'] as String?;
    final maxCaisses      = (payload['max_caisses'] as num?)?.toInt() ?? 1;
    final currentCaisses  = (payload['current_caisses'] as num?)?.toInt() ?? 0;
    final caisseOverLimit = currentCaisses > maxCaisses;
    final priceHtg = (payload['price_per_extra_caisse_htg'] as num?)?.toDouble() ?? 500.0;
    final priceUsd = (payload['price_per_extra_caisse_usd'] as num?)?.toDouble() ?? 4.0;
    final validUntil  = _dt(payload['valid_until']);
    final trialEndsAt = _dt(payload['trial_ends_at']);
    final subEndsAt   = _dt(payload['subscription_ends_at']);

    // Helper to attach tenant/caisse fields to any LicenseStatus
    LicenseStatus withMeta({
      required LicenseAccess access,
      required String status,
      bool isOfflineVal = false,
      int? daysLeft,
      String? message,
    }) =>
        LicenseStatus(
          access: access,
          status: status,
          isOffline: isOfflineVal,
          daysLeft: daysLeft,
          message: message,
          tenantType: tenantType,
          selfHostedUrl: selfHostedUrl,
          maxCaisses: maxCaisses,
          currentCaisses: currentCaisses,
          caisseOverLimit: caisseOverLimit,
          pricePerExtraCaisseHtg: priceHtg,
          pricePerExtraCaisseUsd: priceUsd,
        );

    // 4. Suspended — always blocked
    if (tenantStatus == 'suspended') {
      return withMeta(
        access: LicenseAccess.blocked,
        status: tenantStatus,
        isOfflineVal: isOffline,
        message: 'Votre compte a été suspendu. Contactez le support POS Connect.',
      );
    }

    // 5. Compute days left (trial or subscription)
    final relevantEnd = subEndsAt ?? trialEndsAt;
    int? daysLeft;
    if (relevantEnd != null) {
      final delta = relevantEnd.difference(now);
      daysLeft = delta.inSeconds > 0 ? (delta.inSeconds / 86400).ceil() : 0;
    }

    // 6. License still valid (server-stamped valid_until not reached)
    if (validUntil != null && now.isBefore(validUntil)) {
      if (tenantStatus == 'expired' && !isOffline) {
        return withMeta(
          access: LicenseAccess.warning,
          status: tenantStatus,
          daysLeft: daysLeft,
          message: 'Votre période d\'essai est terminée. Abonnez-vous pour continuer.',
        );
      }
      return withMeta(
        access: LicenseAccess.allowed,
        status: tenantStatus,
        isOfflineVal: isOffline,
        daysLeft: daysLeft,
      );
    }

    // 7. valid_until has passed → offline grace period
    if (validUntil != null) {
      final graceEnd = validUntil.add(const Duration(days: _kOfflineGrace));
      final inGrace  = now.isBefore(graceEnd);
      if (inGrace) {
        final graceDays = (graceEnd.difference(now).inSeconds / 86400).ceil();
        return withMeta(
          access: LicenseAccess.warning,
          status: tenantStatus,
          isOfflineVal: isOffline,
          daysLeft: daysLeft,
          message: isOffline
              ? 'Hors ligne — reconnectez-vous dans $graceDays jour(s) pour valider votre licence.'
              : 'Votre abonnement a expiré. Renouvelez-le pour continuer.',
        );
      }
    }

    // 8. Fully blocked
    return withMeta(
      access: LicenseAccess.blocked,
      status: tenantStatus,
      isOfflineVal: isOffline,
      message: isOffline
          ? 'Reconnectez-vous à internet pour valider votre licence (expirée hors ligne).'
          : 'Votre abonnement a expiré. Veuillez renouveler votre abonnement.',
    );
  }

  // ── Clear cached license (on logout) ──────────────────────────────────────

  static Future<void> clearCache() async {
    await _storage.delete(key: _kDataKey);
    await _storage.delete(key: _kSigKey);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _fetchAndCache() async {
    try {
      final res  = await dio.get('/api/billing/license');
      final data = res.data['data']      as String?;
      final sig  = res.data['signature'] as String?;
      if (data == null || sig == null) return null;
      if (!await _verifySignature(data, sig)) return null;
      await _storage.write(key: _kDataKey, value: data);
      await _storage.write(key: _kSigKey,  value: sig);
      return _decode(data);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _readCached() async {
    final data = await _storage.read(key: _kDataKey);
    final sig  = await _storage.read(key: _kSigKey);
    if (data == null || sig == null) return null;
    if (!await _verifySignature(data, sig)) return null;
    return _decode(data);
  }

  static Future<bool> _verifySignature(String dataB64, String sigB64) async {
    try {
      final pubKeyBytes = base64.decode(AppConstants.identityPublicKeyB64);
      final dataBytes   = base64.decode(dataB64);
      final sigBytes    = base64.decode(sigB64);
      final algorithm   = Ed25519();
      final publicKey   = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      return await algorithm.verify(
        dataBytes,
        signature: Signature(sigBytes, publicKey: publicKey),
      );
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic>? _decode(String dataB64) {
    try {
      return jsonDecode(utf8.decode(base64.decode(dataB64))) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    try { return DateTime.parse(v as String).toUtc(); } catch (_) { return null; }
  }
}
