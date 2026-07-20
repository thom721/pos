import 'dart:io';

import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/shared/widgets/limit_exceeded_dialog.dart';

class OpenSessionDialog extends StatefulWidget {
  final String deviceId;
  final String? warehouseId;
  final String? warehouseName;
  final void Function(Map<String, dynamic> session) onOpened;
  final VoidCallback? onCancelled;

  const OpenSessionDialog({
    super.key,
    required this.deviceId,
    this.warehouseId,
    this.warehouseName,
    required this.onOpened,
    this.onCancelled,
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
      final isNetErr = Platform.isAndroid && (
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
        final localSession = <String, dynamic>{
          'id': const Uuid().v4(),
          'device_id': widget.deviceId,
          'opening_balance': openingBalance,
          'opened_at': DateTime.now().toIso8601String(),
          'offline': true,
        };
        widget.onOpened(localSession);
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // 402 = toutes les caisses occupées → admin confirme
      final confirmed = await handleLimitExceeded(context, e);
      if (!mounted) return;
      if (confirmed) { _open(force: true); return; }

      String msg;
      if (e is DioException) {
        final detail  = e.response?.data?['detail']  as String?;
        final message = e.response?.data?['message'] as String?;
        if (detail == 'caisse_disabled') {
          msg = 'Cette caisse a été désactivée. Contactez votre administrateur.';
        } else if (detail == 'no_registers') {
          msg = message ?? 'Aucune caisse configurée. Contactez l\'administrateur.';
        } else if (detail == 'no_registered_devices') {
          msg = message ?? 'Aucun appareil enregistré comme caisse. Enregistrez d\'abord un appareil dans Business → Caisses.';
        } else {
          msg = message ?? detail ?? 'Erreur réseau';
        }
      } else {
        msg = e.toString();
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
