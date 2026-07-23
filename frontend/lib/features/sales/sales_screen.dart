import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/repositories/return_repository.dart';
import 'package:pos_connect/providers/pos_provider.dart';
import 'package:pos_connect/providers/sale_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/services/bluetooth_print_service.dart';
import 'package:pos_connect/services/thermal_printer_service.dart';
import 'package:pos_connect/shared/utils/receipt_pdf.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/shared/widgets/status_badge.dart';

final _fmt =
    NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _searchCtrl = TextEditingController();
  String? _statusFilter;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesProvider);

    return Column(
      children: [
        // Toolbar
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Rechercher par référence ou client...',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (v) => _updateParams(search: v),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _statusFilter,
                  hint: const Text('Statut'),
                  borderRadius: BorderRadius.circular(8),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tous')),
                    DropdownMenuItem(value: 'PAID', child: Text('Payé')),
                    DropdownMenuItem(value: 'PARTIAL', child: Text('Partiel')),
                    DropdownMenuItem(value: 'UNPAID', child: Text('Impayé')),
                  ],
                  onChanged: (v) {
                    setState(() => _statusFilter = v);
                    _updateParams(status: v);
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // List
        Expanded(
          child: salesAsync.when(
            data: (sales) => sales.data.isEmpty
                ? const Center(
                    child: Text('Aucune vente trouvée',
                        style: TextStyle(color: AppColors.textSecondary)))
                : _SalesList(sales: sales.data, total: sales.meta.total),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Erreur: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
          ),
        ),
      ],
    );
  }

  void _updateParams({String? search, String? status}) {
    ref.read(saleListParamsProvider.notifier).state = SaleListParams(
      page: 1,
      search: search ?? _searchCtrl.text,
      status: status ?? _statusFilter,
    );
  }
}

class _SalesList extends ConsumerWidget {
  final List<SaleModel> sales;
  final int total;

  const _SalesList({required this.sales, required this.total});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: AppColors.surface,
          child: Row(
            children: [
              Text('$total vente${total != 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const Spacer(),
              Text(
                'Total: ${_fmt.format(sales.fold(0.0, (s, e) => s + e.finalAmount))}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Items
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sales.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _SaleCard(sale: sales[i]),
          ),
        ),
      ],
    );
  }
}

class _SaleCard extends ConsumerStatefulWidget {
  final SaleModel sale;

  const _SaleCard({required this.sale});

  @override
  ConsumerState<_SaleCard> createState() => _SaleCardState();
}

class _SaleCardState extends ConsumerState<_SaleCard> {
  bool _printing = false;

  Future<void> _print() async {
    // Web → PDF système directement, pas de modal
    if (kIsWeb) {
      setState(() => _printing = true);
      try {
        final settings = ref.read(settingsProvider);
        final bytes = await buildReceiptPdf(widget.sale, settings);
        await Printing.layoutPdf(
          onLayout: (_) => bytes,
          name: 'Recu_${widget.sale.reference}',
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur impression: $e'),
            backgroundColor: AppColors.error,
          ));
        }
      } finally {
        if (mounted) setState(() => _printing = false);
      }
      return;
    }

    final settings = ref.read(settingsProvider);

    // Android + impression automatique → imprimer directement sans modal
    if (Platform.isAndroid && settings.posAutoPrint) {
      final isSunmi = await ThermalPrinterService.instance.isSunmiAvailable;
      if (isSunmi) {
        setState(() => _printing = true);
        try {
          await ThermalPrinterService.instance.printReceipt(widget.sale, settings);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Impression envoyée'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 2),
            ));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Erreur impression: $e'),
              backgroundColor: AppColors.error,
            ));
          }
        } finally {
          if (mounted) setState(() => _printing = false);
        }
        return;
      }
      if (settings.bluetoothPrinterMac.isNotEmpty) {
        setState(() => _printing = true);
        try {
          final ok = await BluetoothPrintService.instance.printReceipt(
            widget.sale, settings, mac: settings.bluetoothPrinterMac);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(ok
                  ? 'Impression envoyée à ${settings.bluetoothPrinterName}'
                  : 'Connexion imprimante échouée — vérifiez qu\'elle est allumée'),
              backgroundColor: ok ? AppColors.success : AppColors.error,
              duration: const Duration(seconds: 3),
            ));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Erreur: $e'),
              backgroundColor: AppColors.error,
            ));
          }
        } finally {
          if (mounted) setState(() => _printing = false);
        }
        return;
      }
      // Aucune imprimante configurée → ouvrir le modal pour en choisir une
    }

    // Bureau + impression automatique + imprimante configurée → sans modal
    if (!Platform.isAndroid && settings.posAutoPrint &&
        settings.posPrinterName.isNotEmpty) {
      setState(() => _printing = true);
      try {
        await ThermalPrinterService.instance.printReceipt(
          widget.sale, settings,
          printerUrl: settings.posPrinterName,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Impression envoyée'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur impression: $e'),
            backgroundColor: AppColors.error,
          ));
        }
      } finally {
        if (mounted) setState(() => _printing = false);
      }
      return;
    }

    // Modal : auto-print désactivé ou aucune imprimante configurée
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PrintOptionsSheet(
        sale: widget.sale,
        onDone: () {
          if (mounted) setState(() => _printing = false);
        },
      ),
    );
  }

  void _showQuickReturn() {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _QuickReturnDialog(
        sale: widget.sale,
        onSubmit: (items, refund, reason) async {
          await ReturnRepository().createSaleReturn(
            saleId: widget.sale.id,
            items: items,
            refundAmount: refund,
            reason: reason,
          );
          ref.invalidate(salesProvider);
        },
      ),
    ).then((submitted) {
      if (submitted == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Retour enregistré avec succès'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    });
  }

  void _showEditSale() {
    final cart = ref.read(posProvider);
    if (cart.items.isNotEmpty) {
      showDialog<bool>(
        context: context,
        builder: (dlgCtx) => AlertDialog(
          title: const Text('Remplacer le panier ?'),
          content: const Text(
              'Le panier actuel sera vidé et remplacé par cette vente. Continuer ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlgCtx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(dlgCtx, true),
                child: const Text('Remplacer')),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true && mounted) {
          ref.read(posProvider.notifier).loadFromSale(widget.sale);
          context.go('/pos');
        }
      });
    } else {
      ref.read(posProvider.notifier).loadFromSale(widget.sale);
      context.go('/pos');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final isMobile = context.isMobile;

    final actionButtons = [
      IconButton(
        onPressed: _showQuickReturn,
        tooltip: 'Enregistrer un retour',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: const Icon(Icons.assignment_return_rounded,
            color: AppColors.warning, size: 18),
      ),
      IconButton(
        onPressed: _showEditSale,
        tooltip: 'Modifier la vente',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: const Icon(Icons.edit_rounded,
            color: AppColors.info, size: 18),
      ),
      IconButton(
        onPressed: _printing ? null : _print,
        tooltip: 'Imprimer le reçu',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: _printing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.print_rounded,
                color: AppColors.primary, size: 18),
      ),
    ];

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.receipt_rounded,
              color: AppColors.primary, size: 22),
        ),
        title: Text(sale.reference,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sale.customerName ?? 'Client comptoir'} • ${_dateFmt.format(sale.createdAt)}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            if (sale.discount > 0)
              Text(
                'Rabais: -${_fmt.format(sale.discount)}',
                style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
          ],
        ),
        trailing: SizedBox(
          height: 52,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmt.format(sale.finalAmount),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  StatusBadge(status: sale.status),
                ],
              ),
              if (!isMobile) ...[
                const SizedBox(width: 4),
                ...actionButtons,
              ],
            ],
          ),
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          // Items
          ...sale.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: item.returnedQty > 0
                                ? AppColors.warning
                                : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.displayName,
                            style: TextStyle(
                              fontSize: 13,
                              color: item.returnedQty > 0
                                  ? AppColors.textSecondary
                                  : null,
                              decoration: item.returnedQty >= item.quantity
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        // Prix unitaire : barré si rabais
                        if (item.hasDiscount) ...[
                          Text(
                            '${item.quantity.toStringAsFixed(0)} × ${_fmt.format(item.originalPrice!)}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${item.quantity.toStringAsFixed(0)} × ${_fmt.format(item.unitPrice)}',
                            style: const TextStyle(
                                color: AppColors.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ] else
                          Text(
                            '${item.quantity.toStringAsFixed(0)} × ${_fmt.format(item.unitPrice)}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        const SizedBox(width: 12),
                        Text(_fmt.format(item.subtotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    // Ligne rabais article
                    if (item.hasDiscount)
                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Text(
                          'Rabais: -${_fmt.format(item.itemDiscount)}',
                          style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    // Badge retour
                    if (item.returnedQty > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 14, top: 3),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: AppColors.warning.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.assignment_return_rounded,
                                      size: 10, color: AppColors.warning),
                                  const SizedBox(width: 3),
                                  Text(
                                    item.returnedQty >= item.quantity
                                        ? 'Retourné'
                                        : 'Retourné: ${item.returnedQty % 1 == 0 ? item.returnedQty.toInt() : item.returnedQty.toStringAsFixed(2)}/${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // Récapitulatif
          _SaleSummaryRow(sale: sale),
          if (isMobile) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actionButtons,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sale summary row ───────────────────────────────────────────────────────

class _SaleSummaryRow extends StatelessWidget {
  final SaleModel sale;

  const _SaleSummaryRow({required this.sale});

  @override
  Widget build(BuildContext context) {
    // Rabais par article (cumul)
    final itemsDiscount =
        sale.items.fold(0.0, (s, i) => s + i.itemDiscount);
    // Rabais global saisi à la caisse
    final globalDiscount = sale.discount;
    final totalDiscount = itemsDiscount + globalDiscount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Sous-total brut (avant rabais)
        if (totalDiscount > 0) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Sous-total: ',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              Text(
                _fmt.format(sale.totalAmount + itemsDiscount),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          if (itemsDiscount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Rabais articles: ',
                    style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 12)),
                Text(
                  '-${_fmt.format(itemsDiscount)}',
                  style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ],
            ),
          if (globalDiscount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Remise caisse: ',
                    style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 12)),
                Text(
                  '-${_fmt.format(globalDiscount)}',
                  style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ],
            ),
          const SizedBox(height: 2),
        ],
        // Total net + payé
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Total: ${_fmt.format(sale.finalAmount)}  ',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13),
            ),
            Text(
              'Payé: ${_fmt.format(sale.paidAmount)}',
              style: TextStyle(
                  color: sale.balance > 0
                      ? AppColors.error
                      : AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ],
        ),
        if (sale.balance > 0)
          Text(
            'Reste: ${_fmt.format(sale.balance)}',
            style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
                fontSize: 12),
          ),
      ],
    );
  }
}

// ── Quick return dialog (pre-loaded sale, no search) ───────────────────────

class _QuickReturnDialog extends StatefulWidget {
  final SaleModel sale;
  final Future<void> Function(
      List<Map<String, dynamic>> items, double refund, String? reason) onSubmit;

  const _QuickReturnDialog({required this.sale, required this.onSubmit});

  @override
  State<_QuickReturnDialog> createState() => _QuickReturnDialogState();
}

class _QuickReturnDialogState extends State<_QuickReturnDialog> {
  final _reasonCtrl = TextEditingController();
  final _refundCtrl = TextEditingController();
  final Map<int, TextEditingController> _qtyCtrls = {};
  late List<bool> _checked;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = widget.sale.items.length;
    _checked = List.filled(n, false);
    for (var i = 0; i < n; i++) {
      _qtyCtrls[i] = TextEditingController(text: '0');
    }
    _refundCtrl.text = '0';
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _refundCtrl.dispose();
    for (final c in _qtyCtrls.values) { c.dispose(); }
    super.dispose();
  }

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

  double get _computedRefund {
    double total = 0;
    for (var i = 0; i < widget.sale.items.length; i++) {
      final qty = double.tryParse(_qtyCtrls[i]?.text ?? '0') ?? 0;
      total += qty * widget.sale.items[i].unitPrice;
    }
    return total;
  }

  void _updateRefund() =>
      _refundCtrl.text = _computedRefund.toStringAsFixed(2);

  void _onCheck(int i, bool? val) {
    final checked = val ?? false;
    setState(() => _checked[i] = checked);
    final item = widget.sale.items[i];
    final maxQty = (item.quantity - item.returnedQty).clamp(0.0, item.quantity);
    _qtyCtrls[i]!.text = checked ? _fmtQty(maxQty) : '0';
    setState(_updateRefund);
  }

  List<Map<String, dynamic>> get _selectedItems {
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < widget.sale.items.length; i++) {
      final qty = double.tryParse(_qtyCtrls[i]?.text ?? '0') ?? 0;
      if (qty > 0 && widget.sale.items[i].productId != null) {
        result.add({
          'product_id': widget.sale.items[i].productId,
          'quantity': qty,
        });
      }
    }
    return result;
  }

  bool get _canSubmit => _selectedItems.isNotEmpty && !_submitting;

  Future<void> _submit() async {
    setState(() { _submitting = true; _error = null; });
    try {
      await widget.onSubmit(
        _selectedItems,
        double.tryParse(_refundCtrl.text) ?? _computedRefund,
        _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _submitting = false; _error = extractAnyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: const BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Icon(Icons.assignment_return_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Retour — ${sale.reference}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context, false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sale info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.receipt_rounded,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${sale.reference}  •  ${sale.customerName ?? 'Client comptoir'}  •  ${_dateFmt.format(sale.createdAt)}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        const Expanded(
                          child: Text('Articles à retourner',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        // "Tout sélectionner"
                        TextButton(
                          onPressed: () {
                            final returnable = widget.sale.items
                                .asMap()
                                .entries
                                .where((e) =>
                                    (e.value.quantity - e.value.returnedQty) > 0)
                                .map((e) => e.key)
                                .toList();
                            final allChecked =
                                returnable.every((i) => _checked[i]);
                            for (final i in returnable) {
                              _onCheck(i, !allChecked);
                            }
                          },
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0)),
                          child: Text(
                            widget.sale.items.asMap().entries
                                    .where((e) =>
                                        (e.value.quantity -
                                            e.value.returnedQty) >
                                        0)
                                    .every((e) => _checked[e.key])
                                ? 'Tout désélectionner'
                                : 'Tout sélectionner',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Items with checkboxes
                    ...sale.items.asMap().entries.map((e) {
                      final i = e.key;
                      final item = e.value;
                      final ctrl = _qtyCtrls[i]!;
                      final maxQty = (item.quantity - item.returnedQty)
                          .clamp(0.0, item.quantity);
                      final fullyReturned = maxQty <= 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: fullyReturned
                              ? AppColors.divider.withValues(alpha: 0.3)
                              : _checked[i]
                                  ? AppColors.warning.withValues(alpha: 0.06)
                                  : AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _checked[i]
                                ? AppColors.warning.withValues(alpha: 0.4)
                                : AppColors.divider,
                          ),
                        ),
                        child: Row(children: [
                          Checkbox(
                            value: _checked[i],
                            activeColor: AppColors.warning,
                            onChanged: fullyReturned
                                ? null
                                : (v) => _onCheck(i, v),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.displayName,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: fullyReturned
                                            ? AppColors.textSecondary
                                            : null)),
                                Text(
                                  fullyReturned
                                      ? 'Vendu : ${_fmtQty(item.quantity)}  •  Entièrement retourné'
                                      : item.returnedQty > 0
                                          ? 'Vendu : ${_fmtQty(item.quantity)}  •  Déjà retourné : ${_fmtQty(item.returnedQty)}  •  Reste : ${_fmtQty(maxQty)}'
                                          : 'Vendu : ${_fmtQty(item.quantity)}  •  Prix : ${_fmt.format(item.unitPrice)}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 88,
                            child: TextField(
                              controller: ctrl,
                              enabled: !fullyReturned && _checked[i],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: _checked[i]
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Qté retour',
                                isDense: true,
                                helperText: fullyReturned
                                    ? 'retourné'
                                    : 'max ${_fmtQty(maxQty)}',
                              ),
                              onChanged: (_) {
                                final qty =
                                    double.tryParse(ctrl.text) ?? 0;
                                if (qty > maxQty) {
                                  ctrl.text = _fmtQty(maxQty);
                                }
                                if (qty > 0 && !_checked[i]) {
                                  setState(() => _checked[i] = true);
                                }
                                setState(_updateRefund);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                        ]),
                      );
                    }),

                    const Divider(height: 24),

                    // Refund amount (auto-computed, editable)
                    Row(children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Montant remboursé',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            Text('Calculé automatiquement, modifiable',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: _refundCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.accent),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _reasonCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Motif du retour (optionnel)',
                        hintText:
                            'Ex: Produit défectueux, Mauvaise taille...',
                        isDense: true,
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: AppColors.error,
                                      fontSize: 13))),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: AppColors.divider))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.warning),
                    icon: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.assignment_return_rounded,
                            size: 16),
                    label: const Text('Enregistrer le retour'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Print Options Bottom Sheet ────────────────────────────────────────────────

class _PrintOptionsSheet extends ConsumerStatefulWidget {
  final SaleModel sale;
  final VoidCallback onDone;

  const _PrintOptionsSheet({required this.sale, required this.onDone});

  @override
  ConsumerState<_PrintOptionsSheet> createState() => _PrintOptionsSheetState();
}

class _PrintOptionsSheetState extends ConsumerState<_PrintOptionsSheet> {
  List<BluetoothInfo> _btDevices = [];
  bool _scanning = false;
  bool _printing = false;
  bool _isSunmi = false;
  bool _btPermissionDenied = false;
  String? _error;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_isAndroid) _initPrinter();
  }

  Future<void> _initPrinter() async {
    _isSunmi = await ThermalPrinterService.instance.isSunmiAvailable;
    if (mounted) setState(() {});
    // Scanner uniquement si aucune imprimante n'est déjà configurée.
    // Évite un scan Bluetooth inutile (et visible dans la barre de statut)
    // à chaque ouverture du dialog quand l'imprimante est déjà connue.
    if (!_isSunmi && ref.read(settingsProvider).bluetoothPrinterMac.isEmpty) {
      _scanBt();
    }
  }

  Future<void> _printSunmi() async {
    final settings = ref.read(settingsProvider);
    setState(() { _printing = true; _error = null; });
    try {
      await ThermalPrinterService.instance.printReceipt(widget.sale, settings);
      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impression envoyée'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) setState(() { _printing = false; _error = e.toString(); });
    }
  }

  Future<void> _scanBt() async {
    setState(() { _scanning = true; _error = null; _btPermissionDenied = false; });
    try {
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!granted) {
        if (mounted) setState(() { _scanning = false; _btPermissionDenied = true; });
        return;
      }
      _btDevices = await BluetoothPrintService.instance.getPairedPrinters();
    } catch (_) {}
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _printBt(String mac, String name) async {
    var settings = ref.read(settingsProvider);
    // Sauvegarder l'imprimante sélectionnée comme imprimante par défaut
    if (settings.bluetoothPrinterMac != mac) {
      await ref.read(settingsProvider.notifier).save(
            settings.copyWith(
              bluetoothPrinterMac: mac,
              bluetoothPrinterName: name,
            ),
          );
      settings = ref.read(settingsProvider);
    }
    setState(() => _printing = true);
    try {
      final ok = await BluetoothPrintService.instance
          .printReceipt(widget.sale, settings, mac: mac);
      if (mounted) {
        if (ok) {
          Navigator.pop(context);
          widget.onDone();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Impression envoyée à $name'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ));
        } else {
          setState(() => _printing = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '$name ($mac) — connexion échouée après 3 tentatives.\n'
                'Vérifiez que l\'imprimante est allumée et à portée.'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ));
        }
      }
    } catch (e) {
      if (mounted) setState(() { _printing = false; _error = extractAnyError(e); });
    }
  }

  Future<void> _printPdf() async {
    final settings = ref.read(settingsProvider);
    setState(() => _printing = true);
    try {
      final bytes = await buildReceiptPdf(widget.sale, settings);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onDone();
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'Recu_${widget.sale.reference}',
      );
    } catch (e) {
      if (mounted) setState(() { _printing = false; _error = e.toString(); });
    }
  }

  Future<void> _setPaperWidth(int w) async {
    final notifier = ref.read(settingsProvider.notifier);
    final settings = ref.read(settingsProvider);
    await notifier.save(settings.copyWith(paperWidth: w));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsProvider);
    final paperWidth = settings.paperWidth;
    final hasBtConfigured = settings.bluetoothPrinterMac.isNotEmpty;

    final screenH = MediaQuery.of(context).size.height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.80),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            const Icon(Icons.print_rounded, size: 20),
            const SizedBox(width: 8),
            Text('Options d\'impression',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () { Navigator.pop(context); widget.onDone(); },
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const Divider(height: 16),

          // Largeur du papier
          Text('Taille du papier',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                  value: 58,
                  label: Text('58 mm'),
                  icon: Icon(Icons.receipt_outlined, size: 15)),
              ButtonSegment(
                  value: 80,
                  label: Text('80 mm'),
                  icon: Icon(Icons.receipt_long_outlined, size: 15)),
            ],
            selected: {paperWidth},
            onSelectionChanged: (s) => _setPaperWidth(s.first),
          ),

          const SizedBox(height: 16),

          // Imprimante Sunmi intégrée (détectée automatiquement)
          if (_isSunmi) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _printing
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: Colors.white))
                    : const Icon(Icons.print_rounded, size: 18),
                label: const Text('Imprimer (Sunmi)'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success),
                onPressed: _printing ? null : _printSunmi,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 8),
            const SizedBox(height: 4),
          ],

          // Bluetooth (Android uniquement)
          if (_isAndroid) ...[
            Text('Imprimante Bluetooth',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),

            if (hasBtConfigured)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bluetooth_connected_rounded,
                    color: AppColors.accent),
                title: Text(settings.bluetoothPrinterName),
                subtitle: Text(settings.bluetoothPrinterMac,
                    style: const TextStyle(fontSize: 11)),
                trailing: _printing
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : FilledButton.icon(
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Imprimer'),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success),
                        onPressed: () => _printBt(
                            settings.bluetoothPrinterMac,
                            settings.bluetoothPrinterName),
                      ),
              )
            else if (_btPermissionDenied)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  const Icon(Icons.bluetooth_disabled_rounded,
                      size: 18, color: AppColors.error),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Permission Bluetooth refusée.\nParamètres → Apps → POS Connect → Permissions → Appareils à proximité',
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                  ),
                  TextButton(
                    onPressed: _scanBt,
                    child: const Text('Réessayer'),
                  ),
                ]),
              )
            else if (_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Recherche d\'imprimantes…',
                      style: TextStyle(fontSize: 13)),
                ]),
              )
            else if (_btDevices.isNotEmpty)
              ..._btDevices.map((d) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bluetooth_rounded,
                        color: AppColors.textSecondary),
                    title: Text(d.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(d.macAdress,
                        style: const TextStyle(fontSize: 11)),
                    trailing: _printing
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : OutlinedButton(
                            onPressed: () => _printBt(d.macAdress, d.name),
                            child: const Text('Imprimer'),
                          ),
                  ))
            else
              TextButton.icon(
                icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
                label: const Text('Scanner les imprimantes appairées'),
                onPressed: _scanBt,
              ),

            const SizedBox(height: 8),
          ],

          // Impression PDF / système
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Impression PDF / Système'),
              onPressed: _printing ? null : _printPdf,
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(
                    color: AppColors.error, fontSize: 12)),
          ],
        ],
      ),
    ),
    );
  }
}

