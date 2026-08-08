import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/transfer_receipt_model.dart';
import 'package:pos_connect/providers/entrepot_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/shared/utils/transfer_pdf.dart';

/// Envoie une quantité de [productId] vers un entrepôt, depuis n'importe quel
/// emplacement (dépôt classique ou autre entrepôt — [sourceWarehouseId]).
/// Réutilisé par la fiche produit (« Retourner à l'entrepôt ») et l'écran
/// Entrepôt (« Transférer vers un autre entrepôt ») — même flux, même reçu
/// imprimable pour audit.
Future<void> showTransferToEntrepotDialog(
  BuildContext context,
  WidgetRef ref, {
  required String productId,
  required String productName,
  required String sourceWarehouseId,
  String? excludeEntrepotId,
  VoidCallback? onDone,
}) {
  return showDialog(
    context: context,
    builder: (_) => _TransferToEntrepotDialog(
      productId: productId,
      productName: productName,
      sourceWarehouseId: sourceWarehouseId,
      excludeEntrepotId: excludeEntrepotId,
      onDone: onDone,
    ),
  );
}

class _TransferToEntrepotDialog extends ConsumerStatefulWidget {
  final String productId;
  final String productName;
  final String sourceWarehouseId;
  final String? excludeEntrepotId;
  final VoidCallback? onDone;

  const _TransferToEntrepotDialog({
    required this.productId,
    required this.productName,
    required this.sourceWarehouseId,
    this.excludeEntrepotId,
    this.onDone,
  });

  @override
  ConsumerState<_TransferToEntrepotDialog> createState() =>
      _TransferToEntrepotDialogState();
}

class _TransferToEntrepotDialogState
    extends ConsumerState<_TransferToEntrepotDialog> {
  final _qtyCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String? _targetId;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.'));
    if (_targetId == null) {
      setState(() => _error = 'Choisissez un entrepôt de destination');
      return;
    }
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Entrez une quantité valide');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final receipt = await ref.read(entrepotRepositoryProvider).transferIn(
            _targetId!, widget.productId, widget.sourceWarehouseId, qty,
            reason: _reasonCtrl.text.trim(),
          );
      widget.onDone?.call();
      if (mounted) {
        Navigator.pop(context);
        _offerPrint(context, ref, receipt);
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Erreur lors du transfert'; });
    }
  }

  void _offerPrint(BuildContext context, WidgetRef ref, TransferReceiptModel receipt) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Transfert vers ${receipt.targetName} effectué'),
      backgroundColor: AppColors.success,
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'IMPRIMER',
        textColor: Colors.white,
        onPressed: () async {
          final settings = ref.read(settingsProvider);
          final bytes = await buildTransferPdf(receipt, settings);
          await Printing.layoutPdf(
            onLayout: (_) => bytes,
            name: 'Transfert_${receipt.movementId.substring(0, 8)}',
          );
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final entrepotsAsync = ref.watch(entrepotsProvider);

    return AlertDialog(
      title: Text('Transférer — ${widget.productName}', style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            entrepotsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Text('Erreur : $e',
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
              data: (all) {
                final entrepots =
                    all.where((e) => e.id != widget.excludeEntrepotId).toList();
                if (entrepots.isEmpty) {
                  return const Text('Aucun entrepôt disponible.',
                      style: TextStyle(color: AppColors.textSecondary));
                }
                _targetId ??= entrepots.first.id;
                return DropdownButtonFormField<String>(
                  initialValue: _targetId,
                  decoration: const InputDecoration(labelText: 'Entrepôt de destination'),
                  items: entrepots
                      .map((e) => DropdownMenuItem(value: e.id, child: Text(e.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _targetId = v),
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _qtyCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantité'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(labelText: 'Motif (optionnel)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Transférer'),
        ),
      ],
    );
  }
}
