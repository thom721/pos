import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';

final _fmtHtg = NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);
final _fmtUsd = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

/// Returns true if user confirmed, false if cancelled.
/// Shows nothing and returns false if [error] is not a 402 limit_exceeded.
Future<bool> handleLimitExceeded(BuildContext context, dynamic error) async {
  if (error is! DioException) return false;
  if (error.response?.statusCode != 402) return false;
  final data = error.response?.data as Map<String, dynamic>?;
  if (data?['detail'] != 'limit_exceeded') return false;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LimitExceededDialog(
      resource: data!['resource'] as String? ?? 'caisse',
      current:  (data['current']  as num?)?.toInt() ?? 0,
      max:      (data['max']       as num?)?.toInt() ?? 1,
      priceHtg: (data['price_htg'] as num?)?.toDouble() ?? 500,
      priceUsd: (data['price_usd'] as num?)?.toDouble() ?? 4,
    ),
  );
  return confirmed == true;
}

class _LimitExceededDialog extends StatefulWidget {
  final String resource;
  final int current;
  final int max;
  final double priceHtg;
  final double priceUsd;

  const _LimitExceededDialog({
    required this.resource,
    required this.current,
    required this.max,
    required this.priceHtg,
    required this.priceUsd,
  });

  @override
  State<_LimitExceededDialog> createState() => _LimitExceededDialogState();
}

class _LimitExceededDialogState extends State<_LimitExceededDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final res     = widget.resource;
    final resPlur = res == 'caisse' ? 'caisses' : 'dépôts';
    final resArt  = res == 'caisse' ? 'une caisse' : 'un dépôt';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('Limite dépassée',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current vs max banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Votre plan inclut ${widget.max} $resPlur. '
                      'Vous en avez actuellement ${widget.current}.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Cost increase
            Text(
              'Créer $resArt supplémentaire augmentera votre prochaine facture de :',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _PriceTag(
                    value: _fmtHtg.format(widget.priceHtg),
                    color: AppColors.primary),
                const SizedBox(width: 12),
                _PriceTag(
                    value: _fmtUsd.format(widget.priceUsd),
                    color: AppColors.info),
              ],
            ),
            const SizedBox(height: 20),

            // Mandatory checkbox
            InkWell(
              onTap: () => setState(() => _accepted = !_accepted),
              borderRadius: BorderRadius.circular(6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _accepted,
                    activeColor: AppColors.primary,
                    onChanged: (v) =>
                        setState(() => _accepted = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Je comprends que ma prochaine facture sera augmentée '
                        'et j\'accepte cette modification tarifaire.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _accepted ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            disabledBackgroundColor:
                AppColors.warning.withValues(alpha: 0.35),
          ),
          child: const Text('Créer quand même'),
        ),
      ],
    );
  }
}

class _PriceTag extends StatelessWidget {
  final String value;
  final Color color;
  const _PriceTag({required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const Text('/mois',
                style: TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      );
}
