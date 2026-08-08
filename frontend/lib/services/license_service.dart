import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
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
    bool serverReachable = false;
    Map<String, dynamic>? payload;
    try {
      payload = await _fetchAndCache();
      serverReachable = true; // reached server (got a valid response)
    } on DioException catch (e) {
      // Server responded with an error (4xx/5xx) — device is online, billing is broken
      serverReachable = e.response != null;
    } catch (_) {}

    final isOffline = payload == null && !serverReachable;

    // 2. Fall back to signed cache
    if (payload == null) payload = await _readCached();

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
    final registers    = payload['registers'] as List<dynamic>? ?? [];

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

    // 4. Suspended — avertissement seulement, l'app reste accessible
    // Les ventes sont bloquées côté backend (402). On n'affiche plus l'écran de blocage.
    //
    // tenant.status est un champ hérité, plus tenu à jour depuis le passage à
    // la facturation par caisse (voir le commentaire au point 6 ci-dessous) —
    // il peut rester bloqué sur "suspended" alors que toutes les caisses ont
    // été payées individuellement depuis. On préfère donc le même détail par
    // caisse (registers) qu'au point 6, avant de se rabattre sur le message
    // générique.
    if (tenantStatus == 'suspended') {
      final registerMessage = !isOffline ? _registerIssueMessage(registers, now) : null;
      if (registerMessage != null) {
        return withMeta(
          access: LicenseAccess.warning,
          status: tenantStatus,
          message: registerMessage,
        );
      }
      if (!isOffline && registers.isNotEmpty) {
        // "suspended" mais aucune caisse n'a de problème actuellement —
        // champ legacy pas remis à jour, ne pas alarmer inutilement.
        return withMeta(
          access: LicenseAccess.allowed,
          status: tenantStatus,
          isOfflineVal: isOffline,
        );
      }
      // Fallback générique — pas de détail par caisse disponible (payload
      // minimal, hors ligne, ou tenant sans caisse du tout).
      return withMeta(
        access: LicenseAccess.warning,
        status: tenantStatus,
        isOfflineVal: isOffline,
        message: 'Votre compte est suspendu. Renouvelez votre abonnement pour retrouver l\'accès aux ventes.',
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
      // Le statut tenant (trial/expired) est un champ hérité, plus tenu à
      // jour depuis le passage à la facturation par caisse — il peut dire
      // "expired" alors qu'une caisse a encore des jours d'essai valides.
      // On préfère donc le détail par caisse (registers) quand disponible :
      // message précis (caisse concernée, essai ou abonnement, avertissement
      // ou erreur) au lieu d'un message générique et parfois faux.
      final registerMessage = !isOffline ? _registerIssueMessage(registers, now) : null;
      if (registerMessage != null) {
        return withMeta(
          access: LicenseAccess.warning,
          status: tenantStatus,
          daysLeft: daysLeft,
          message: registerMessage,
        );
      }
      if (tenantStatus == 'expired' && !isOffline && registers.isEmpty) {
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

    // 7. valid_until has passed — le blob doit être rafraîchi.
    //
    //    CAS A : abonnement payé encore valide (subEndsAt dans le futur)
    //    → autoriser l'accès jusqu'à subEndsAt, même sans internet.
    //    Le blob ne sert qu'à re-vérification périodique ; la date de fin
    //    d'abonnement est la vraie borne.
    //
    //    CAS B : essai / pas d'abonnement → grâce courte de _kOfflineGrace jours.
    if (subEndsAt != null &&
        now.isBefore(subEndsAt) &&
        tenantStatus == 'active') {
      // Abonnement payé, encore dans sa période → accès autorisé hors ligne
      final subDaysLeft = (subEndsAt.difference(now).inSeconds / 86400).ceil();
      return withMeta(
        access: LicenseAccess.allowed,
        status: tenantStatus,
        isOfflineVal: isOffline,
        daysLeft: subDaysLeft,
        message: isOffline
            ? 'Mode hors ligne — abonnement valide jusqu\'au ${_fmtDate(subEndsAt)}. '
              'Reconnectez-vous pour synchroniser.'
            : null,
      );
    }

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
    try { await _storage.delete(key: _kDataKey); } catch (_) {}
    try { await _storage.delete(key: _kSigKey); } catch (_) {}
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _fetchAndCache() async {
    try {
      final res  = await dio.get('/api/billing/license');
      final data = res.data['data']      as String?;
      final sig  = res.data['signature'] as String?;
      if (data == null || sig == null) return null;
      if (!await _verifySignature(data, sig)) return null;
      try {
        await _storage.write(key: _kDataKey, value: data);
        await _storage.write(key: _kSigKey,  value: sig);
      } catch (_) {}
      return _decode(data);
    } on DioException catch (e) {
      // Server responded with an error (4xx/5xx) → server is reachable, not offline.
      // Re-throw so check() knows this is a server error, not a network issue.
      if (e.response != null) rethrow;
      return null; // network unreachable → treat as offline
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _readCached() async {
    try {
      final data = await _storage.read(key: _kDataKey);
      final sig  = await _storage.read(key: _kSigKey);
      if (data == null || sig == null) return null;
      if (!await _verifySignature(data, sig)) return null;
      return _decode(data);
    } catch (_) {
      return null;
    }
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

  // Nombre de jours avant expiration à partir duquel on avertit — aligné
  // sur WARN_DAYS côté backend (api/core/tenant.py).
  static const int _kWarnDays = 5;

  /// Construit un message précis à partir du détail par caisse (`registers`),
  /// nommant la ou les caisses concernées et précisant s'il s'agit d'un
  /// avertissement (bientôt expiré) ou d'une erreur (déjà sans abonnement).
  /// Retourne null si aucune caisse n'a de problème.
  static String? _registerIssueMessage(List<dynamic> registers, DateTime now) {
    final expired = <String>[];
    final expiringSoon = <String>[];

    for (final r in registers) {
      if (r is! Map) continue;
      // Le nom de la CAISSE d'abord (r['name']) — warehouse_name n'est que le
      // dépôt auquel elle appartient, pas un nom de caisse. Les inverser
      // affichait le nom du dépôt à la place du nom de la caisse concernée.
      final registerName = (r['name'] as String?) ?? 'Caisse';
      final warehouseName = r['warehouse_name'] as String?;
      final name = (warehouseName != null && warehouseName != registerName)
          ? '$registerName ($warehouseName)'
          : registerName;
      final status = r['status'] as String? ?? '';

      if (status == 'expired' || status == 'no_subscription') {
        expired.add(name);
        continue;
      }

      final endRaw = (r['subscription_ends_at'] as String?) ??
          (r['trial_ends_at'] as String?);
      final end = endRaw != null ? DateTime.tryParse(endRaw) : null;
      if (end != null) {
        final daysLeft = end.difference(now).inDays;
        if (daysLeft >= 0 && daysLeft <= _kWarnDays) {
          final kind = status == 'active' ? 'abonnement' : 'période d\'essai';
          expiringSoon.add('$name ($kind, $daysLeft j)');
        }
      }
    }

    if (expired.isEmpty && expiringSoon.isEmpty) return null;

    final parts = <String>[];
    if (expired.isNotEmpty) {
      // "Erreur" évoque un problème technique/système et inquiète inutilement
      // le client — il s'agit d'un abonnement à payer, pas d'un dysfonctionnement.
      final label = expired.length > 1 ? 'Caisses' : 'Caisse';
      parts.add('Abonnement requis : $label ${expired.join(', ')} sans abonnement actif.');
    }
    if (expiringSoon.isNotEmpty) {
      final label = expiringSoon.length > 1 ? 'Caisses' : 'Caisse';
      parts.add('Bientôt à renouveler : $label ${expiringSoon.join(', ')} bientôt expiré(e)s.');
    }
    return '${parts.join(' ')} Gérez vos caisses dans Abonnement.';
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

  static String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
           '${local.month.toString().padLeft(2, '0')}/'
           '${local.year}';
  }
}
