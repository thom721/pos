import 'dart:io';

import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pos_connect/core/register_date_crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/shared/widgets/limit_exceeded_dialog.dart';

class OpenSessionDialog extends StatefulWidget {
  final String deviceId;
  final String userId;
  final String? warehouseId;
  final String? warehouseName;
  final void Function(Map<String, dynamic> session) onOpened;
  final VoidCallback? onCancelled;
  final bool isAdminOrManager;

  const OpenSessionDialog({
    super.key,
    required this.deviceId,
    required this.userId,
    this.warehouseId,
    this.warehouseName,
    required this.onOpened,
    this.onCancelled,
    this.isAdminOrManager = false,
  });

  @override
  State<OpenSessionDialog> createState() => _OpenSessionDialogState();
}

class _OpenSessionDialogState extends State<OpenSessionDialog> {
  final _balanceCtrl = TextEditingController(text: '0');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _open({bool force = false}) async {
    setState(() { _loading = true; _error = null; });
    final openingBalance = double.tryParse(_balanceCtrl.text) ?? 0;
    try {
      final res = await dio.post('/api/sessions/open', data: {
        'device_id': widget.deviceId,
        'register_name': 'Caisse',
        'opening_balance': openingBalance,
        'force': force,
        if (widget.warehouseId != null) 'warehouse_id': widget.warehouseId,
      });
      final session = res.data['session'] as Map<String, dynamic>;
      widget.onOpened(session);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      // Réseau indisponible sur Android → session locale si l'appareil est enregistré
      final isNetErr = !kIsWeb && Platform.isAndroid && (
        e is DioException && (
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.unknown
        ) || e is SocketException
      );
      if (isNetErr) {
        final prefs = await SharedPreferences.getInstance();
        final regKey = 'pos_has_register_${widget.warehouseId ?? 'default'}';
        final isRegistered = prefs.getBool(regKey) ?? false;
        if (!isRegistered) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Appareil non enregistré comme caisse. '
                'Connectez-vous au réseau une première fois pour activer cet appareil.';
          });
          return;
        }

        // Vérifier le caissier dédié depuis le cache signé.
        final dedicatedRaw = prefs.getString('${regKey}_dedicated');
        final dedicatedIso = await verifyDate(dedicatedRaw, widget.deviceId);
        if (dedicatedIso != null && dedicatedIso.isNotEmpty && dedicatedIso != widget.userId) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Cette caisse est réservée à un autre caissier.';
          });
          return;
        }

        // Vérifier l'abonnement depuis le cache.
        // Les dates sont signées HMAC-SHA256(device_id) — si le token est
        // altéré dans SharedPreferences, verifyDate() retourne null → bloqué.
        final trialRaw = prefs.getString('${regKey}_trial');
        final subRaw   = prefs.getString('${regKey}_sub');
        final trialIso = await verifyDate(trialRaw, widget.deviceId);
        final subIso   = await verifyDate(subRaw,   widget.deviceId);
        final now      = DateTime.now().toUtc();
        final trialEnd = trialIso != null ? DateTime.tryParse(trialIso)?.toUtc() : null;
        final subEnd   = subIso   != null ? DateTime.tryParse(subIso)?.toUtc()   : null;
        final hasTrial = trialEnd != null && trialEnd.isAfter(now);
        final hasSub   = subEnd   != null && subEnd.isAfter(now);

        if (!hasTrial && !hasSub) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Abonnement de cette caisse expiré. '
                'Reconnectez-vous au réseau pour renouveler.';
          });
          return;
        }

        final localSession = <String, dynamic>{
          'id': const Uuid().v4(),
          'device_id': widget.deviceId,
          'opening_balance': openingBalance,
          'opened_at': DateTime.now().toUtc().toIso8601String(),
          'offline': true,
        };
        widget.onOpened(localSession);
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // 402 = toutes les caisses occupées
      if (e is DioException && e.response?.statusCode == 402 &&
          e.response?.data?['detail'] == 'limit_exceeded') {
        if (!widget.isAdminOrManager) {
          // Le caissier ne peut pas créer de caisse — informer seulement
          setState(() {
            _loading = false;
            _error = 'Aucune caisse disponible. Contactez votre administrateur pour en libérer ou en créer une.';
          });
          return;
        }
        // Admin/manager → proposer la création
        final confirmed = await handleLimitExceeded(context, e);
        if (!mounted) return;
        if (confirmed) { _open(force: true); return; }
        setState(() => _loading = false);
        return;
      }

      String msg;
      if (e is DioException) {
        final detail  = e.response?.data?['detail']  as String?;
        final message = e.response?.data?['message'] as String?;
        if (detail == 'caisse_disabled') {
          msg = 'Cette caisse a été désactivée. Contactez votre administrateur.';
        } else if (detail == 'register_dedicated') {
          msg = message ?? 'Cette caisse est réservée à un autre caissier.';
        } else if (detail == 'register_no_subscription') {
          msg = message ?? 'Cette caisse n\'a pas d\'abonnement actif. Payez l\'abonnement depuis la page Abonnement.';
        } else if (detail == 'no_registers') {
          msg = message ?? 'Aucune caisse configurée. Contactez l\'administrateur.';
        } else if (detail == 'no_registered_devices') {
          msg = message ?? 'Aucun appareil enregistré comme caisse. Enregistrez d\'abord un appareil dans Business → Caisses.';
        } else if (detail == 'device_pending_approval') {
          msg = message ?? 'Cet appareil doit être approuvé par un administrateur avant de pouvoir ouvrir une caisse.';
        } else if (detail == 'device_bound_elsewhere') {
          msg = message ?? 'Cet appareil est déjà enregistré pour un autre dépôt.';
        } else {
          msg = message ?? detail ?? 'Erreur réseau';
        }
      } else {
        msg = extractAnyError(e);
      }
      setState(() { _loading = false; _error = msg; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.point_of_sale_rounded,
              color: AppColors.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ouvrir la caisse',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              if (widget.warehouseName != null)
                Text(widget.warehouseName!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary,
                        fontWeight: FontWeight.normal)),
            ],
          ),
        ),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Saisissez le fond de caisse (espèces disponibles au démarrage).',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _balanceCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Fond de caisse',
              prefixIcon: Icon(Icons.payments_outlined, size: 20),
              isDense: true,
            ),
            onSubmitted: (_) => _open(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        if (widget.onCancelled != null)
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onCancelled!();
                  },
            child: const Text('Annuler'),
          ),
        FilledButton(
          onPressed: _loading ? null : _open,
          child: _loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Ouvrir la caisse'),
        ),
      ],
    );
  }
}
