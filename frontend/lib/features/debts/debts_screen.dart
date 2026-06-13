import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/debt_model.dart';
import 'package:pos_connect/data/repositories/sale_repository.dart';
import 'package:pos_connect/providers/debt_provider.dart';
import 'package:pos_connect/providers/payment_provider.dart';
import 'package:pos_connect/shared/widgets/status_badge.dart';

final _fmt =
    NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);
final _dateFmt = DateFormat('dd/MM/yyyy');
final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');

class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  String? _partnerType;
  String? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final debtsAsync = ref.watch(debtsProvider);

    return Column(
      children: [
        // Filters
        Container(
          color: AppColors.surface,
          padding: EdgeInsets.all(context.hPad),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Filtres :',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 13)),
              _FilterChip(
                label: 'Clients',
                selected: _partnerType == 'CUSTOMER',
                onTap: () {
                  setState(() => _partnerType =
                      _partnerType == 'CUSTOMER' ? null : 'CUSTOMER');
                  _update();
                },
              ),
              _FilterChip(
                label: 'Fournisseurs',
                selected: _partnerType == 'SUPPLIER',
                onTap: () {
                  setState(() => _partnerType =
                      _partnerType == 'SUPPLIER' ? null : 'SUPPLIER');
                  _update();
                },
              ),
              _FilterChip(
                label: 'Impayées',
                selected: _statusFilter == 'UNPAID',
                color: AppColors.error,
                onTap: () {
                  setState(() => _statusFilter =
                      _statusFilter == 'UNPAID' ? null : 'UNPAID');
                  _update();
                },
              ),
              _FilterChip(
                label: 'Partielles',
                selected: _statusFilter == 'PARTIAL',
                color: AppColors.warning,
                onTap: () {
                  setState(() => _statusFilter =
                      _statusFilter == 'PARTIAL' ? null : 'PARTIAL');
                  _update();
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Summary
        debtsAsync.when(
          data: (debts) {
            final totalBalance =
                debts.data.fold(0.0, (s, d) => s + d.balance);
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              color: AppColors.surface,
              child: Row(
                children: [
                  Text(
                      '${debts.meta.total} dette${debts.meta.total != 1 ? 's' : ''}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const Spacer(),
                  Text(
                    'Solde total: ${_fmt.format(totalBalance)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: totalBalance > 0
                          ? AppColors.error
                          : AppColors.accent,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, st) => const SizedBox.shrink(),
        ),
        const Divider(height: 1),

        // List
        Expanded(
          child: debtsAsync.when(
            data: (debts) => debts.data.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            size: 48, color: AppColors.accent),
                        SizedBox(height: 12),
                        Text('Aucune dette',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: debts.data.length,
                    separatorBuilder: (ctx, i) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _DebtCard(debt: debts.data[i]),
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Erreur: $e',
                    style: const TextStyle(color: AppColors.error))),
          ),
        ),
      ],
    );
  }

  void _update() {
    ref.read(debtListParamsProvider.notifier).state = DebtListParams(
      partnerType: _partnerType,
      status: _statusFilter,
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.1) : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? c : AppColors.divider,
              width: selected ? 1.5 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : AppColors.textSecondary,
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Debt card ──────────────────────────────────────────────────────────────

class _DebtCard extends ConsumerStatefulWidget {
  final DebtModel debt;

  const _DebtCard({required this.debt});

  @override
  ConsumerState<_DebtCard> createState() => _DebtCardState();
}

class _DebtCardState extends ConsumerState<_DebtCard> {
  bool _paying = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.debt;
    final isCustomer = d.partnerType == 'CUSTOMER';
    final displayName = d.partnerName ??
        (isCustomer ? 'Client' : 'Fournisseur');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main row ─────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCustomer
                        ? Icons.person_rounded
                        : Icons.local_shipping_rounded,
                    color: AppColors.error,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),

                // Name + details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              d.referenceType,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total: ${_fmt.format(d.totalAmount)}  •  Payé: ${_fmt.format(d.paidAmount)}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      Text(
                        _dateFmt.format(d.createdAt),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),

                // Balance + status
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmt.format(d.balance),
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StatusBadge(status: d.status),
                  ],
                ),
              ],
            ),

            // ── Action row ────────────────────────────────────────
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                // Historique button
                SizedBox(
                  height: 30,
                  child: TextButton.icon(
                    onPressed: () => _showHistory(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(Icons.history_rounded, size: 15),
                    label: const Text('Historique'),
                  ),
                ),
                const Spacer(),
                // Encaisser button
                if (d.balance > 0)
                  SizedBox(
                    height: 30,
                    child: OutlinedButton.icon(
                      onPressed: _paying
                          ? null
                          : () => _showPaymentDialog(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 0),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      icon: _paying
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent),
                            )
                          : const Icon(Icons.payment_rounded, size: 14),
                      label: Text(_paying ? 'En cours...' : 'Encaisser'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) =>
          _PaymentHistoryDialog(debt: widget.debt),
    );
  }

  void _showPaymentDialog(BuildContext context) {
    final ctrl = TextEditingController(
        text: widget.debt.balance.toStringAsFixed(2));
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Ajouter un paiement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Montant (HTG)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(ctrl.text) ?? 0;
              if (amount <= 0) return;
              Navigator.pop(dialogCtx);
              setState(() => _paying = true);
              try {
                await SaleRepository().addPayment(
                  referenceType: widget.debt.referenceType,
                  referenceId: widget.debt.referenceId,
                  amount: amount,
                  method: 'CASH',
                );
                ref.invalidate(debtsProvider);
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Erreur lors du paiement'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _paying = false);
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }
}

// ── Payment history dialog ─────────────────────────────────────────────────

class _PaymentHistoryDialog extends ConsumerWidget {
  final DebtModel debt;

  const _PaymentHistoryDialog({required this.debt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(
      paymentHistoryProvider((debt.referenceType, debt.referenceId)),
    );
    final isCustomer = debt.partnerType == 'CUSTOMER';
    final displayName =
        debt.partnerName ?? (isCustomer ? 'Client' : 'Fournisseur');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.history_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Historique des paiements',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Text(
                          displayName,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                        foregroundColor: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Summary strip
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              color: AppColors.background,
              child: Row(
                children: [
                  _SummaryChip(
                    label: 'Total',
                    value: _fmt.format(debt.totalAmount),
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: 16),
                  _SummaryChip(
                    label: 'Payé',
                    value: _fmt.format(debt.paidAmount),
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 16),
                  _SummaryChip(
                    label: 'Reste',
                    value: _fmt.format(debt.balance),
                    color: debt.balance > 0
                        ? AppColors.error
                        : AppColors.success,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Payment list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: paymentsAsync.when(
                data: (payments) => payments.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.receipt_outlined,
                                  size: 40,
                                  color: AppColors.textSecondary),
                              SizedBox(height: 10),
                              Text(
                                'Aucun paiement enregistré',
                                style: TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: payments.length,
                        separatorBuilder: (ctx, i) =>
                            const Divider(height: 1, indent: 20),
                        itemBuilder: (ctx, i) {
                          final p = payments[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            child: Row(
                              children: [
                                // Method icon
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.accent
                                        .withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _methodIcon(p.method),
                                    color: AppColors.accent,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Date + caissier
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _dtFmt.format(p.createdAt),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 6,
                                                vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.info
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              p.methodLabel,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.info,
                                                  fontWeight:
                                                      FontWeight.w600),
                                            ),
                                          ),
                                          if (p.userFullName != null) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              p.userFullName!,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors
                                                      .textSecondary),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Amount
                                Text(
                                  _fmt.format(p.amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Erreur: $e',
                      style: const TextStyle(color: AppColors.error)),
                ),
              ),
            ),

            // Footer
            const Divider(height: 1),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _methodIcon(String method) {
    switch (method.toUpperCase()) {
      case 'CASH':
        return Icons.payments_rounded;
      case 'BANK':
        return Icons.account_balance_rounded;
      case 'MOBILE':
        return Icons.phone_android_rounded;
      default:
        return Icons.payment_rounded;
    }
  }
}

// ── Summary chip ───────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color)),
      ],
    );
  }
}
