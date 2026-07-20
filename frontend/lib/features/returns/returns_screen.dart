import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/return_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/data/models/purchase_model.dart';
import 'package:pos_connect/data/repositories/return_repository.dart';
import 'package:pos_connect/providers/return_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';
import 'package:pos_connect/shared/utils/return_pdf.dart';

final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

NumberFormat _fmtCurrency(String symbol) =>
    NumberFormat.currency(locale: 'fr_HT', symbol: '$symbol ', decimalDigits: 2);

String _fmtQty(double q) =>
    q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

// ── Screen ─────────────────────────────────────────────────────────────────

class ReturnsScreen extends ConsumerStatefulWidget {
  const ReturnsScreen({super.key});

  @override
  ConsumerState<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends ConsumerState<ReturnsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  bool get _isSaleTab => _tab.index == 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(returnsProvider);
    final settings = ref.watch(settingsProvider);
    final fmt = _fmtCurrency(settings.currencySymbol);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Header ──
          Container(
            color: AppColors.surface,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Retours',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700)),
                            Text(
                              _isSaleTab
                                  ? '${state.saleReturns.length} retour(s) client'
                                  : '${state.purchaseReturns.length} retour(s) fournisseur',
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (state.loading) ...[
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton.icon(
                        onPressed: () => _showNewReturnDialog(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(_isSaleTab
                            ? 'Retour client'
                            : 'Retour fournisseur'),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tab,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  tabs: [
                    Tab(text: 'Retours clients (${state.saleReturns.length})'),
                    Tab(
                        text:
                            'Retours fournisseurs (${state.purchaseReturns.length})'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Content ──
          Expanded(
            child: state.error != null
                ? _ErrorBanner(
                    message: state.error!,
                    onRetry: () => ref.read(returnsProvider.notifier).fetch(),
                  )
                : TabBarView(
                    controller: _tab,
                    children: [
                      _ReturnsList(
                        returns: state.saleReturns,
                        fmt: fmt,
                        type: 'sale',
                      ),
                      _ReturnsList(
                        returns: state.purchaseReturns,
                        fmt: fmt,
                        type: 'purchase',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _showNewReturnDialog(BuildContext context) {
    final warehouseId = ref.read(activeWarehouseProvider)?.id;
    if (_isSaleTab) {
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NewSaleReturnDialog(
          onSubmit: (saleId, items, refund, reason) =>
              ref.read(returnsProvider.notifier).createSaleReturn(
                saleId: saleId,
                items: items,
                refundAmount: refund,
                reason: reason,
                warehouseId: warehouseId,
              ),
        ),
      ).then((ok) {
        if ((ok ?? false) && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Retour client enregistré'),
                backgroundColor: AppColors.success),
          );
        }
      });
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NewPurchaseReturnDialog(
          onSubmit: (purchaseId, items, reason) async {
            final ok = await ref
                .read(returnsProvider.notifier)
                .createPurchaseReturn(
                  purchaseId: purchaseId,
                  items: items,
                  reason: reason,
                  warehouseId: warehouseId,
                );
            if (ok && context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Retour fournisseur enregistré'),
                    backgroundColor: AppColors.success),
              );
            }
          },
        ),
      );
    }
  }
}

// ── Returns list ───────────────────────────────────────────────────────────

class _ReturnsList extends StatelessWidget {
  final List<ReturnModel> returns;
  final NumberFormat fmt;
  final String type;

  const _ReturnsList(
      {required this.returns, required this.fmt, required this.type});

  @override
  Widget build(BuildContext context) {
    if (returns.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'sale'
                  ? Icons.assignment_return_outlined
                  : Icons.undo_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              type == 'sale'
                  ? 'Aucun retour client'
                  : 'Aucun retour fournisseur',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              type == 'sale'
                  ? 'Enregistrez le retour d\'un client ici'
                  : 'Enregistrez un retour vers un fournisseur ici',
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: returns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) =>
          _ReturnCard(ret: returns[i], fmt: fmt, type: type),
    );
  }
}

// ── Return card ────────────────────────────────────────────────────────────

class _ReturnCard extends ConsumerStatefulWidget {
  final ReturnModel ret;
  final NumberFormat fmt;
  final String type;

  const _ReturnCard(
      {required this.ret, required this.fmt, required this.type});

  @override
  ConsumerState<_ReturnCard> createState() => _ReturnCardState();
}

class _ReturnCardState extends ConsumerState<_ReturnCard> {
  bool _printing = false;

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final settings = ref.read(settingsProvider);
      final bytes = await buildReturnPdf(widget.ret, settings);
      final s = ref.read(settingsProvider);
      if (s.docPrinterName.isNotEmpty) {
        final printers = await Printing.listPrinters();
        final printer = printers.cast<Printer?>().firstWhere(
          (p) => p?.url == s.docPrinterName,
          orElse: () => null,
        );
        if (printer != null) {
          await Printing.directPrintPdf(
            printer: printer,
            onLayout: (_) => bytes,
            name: 'Retour_${widget.ret.docReference}',
          );
          return;
        }
      }
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'Retour_${widget.ret.docReference}',
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ret = widget.ret;
    final fmt = widget.fmt;
    final isSale = widget.type == 'sale';

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      clipBehavior: Clip.hardEdge,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (isSale ? AppColors.warning : AppColors.info)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isSale
                ? Icons.assignment_return_rounded
                : Icons.undo_rounded,
            color: isSale ? AppColors.warning : AppColors.info,
            size: 22,
          ),
        ),
        title: Text(
          ret.docReference,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _dateFmt.format(ret.createdAt),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            if (ret.reason != null && ret.reason!.isNotEmpty)
              Text(
                'Motif : ${ret.reason}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fmt.format(ret.totalReturned),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                if (isSale && ret.refundAmount > 0)
                  Text(
                    'Remboursé : ${fmt.format(ret.refundAmount)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.success),
                  ),
              ],
            ),
            // Print button (sale returns only)
            if (isSale) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: _printing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_rounded, size: 18),
                tooltip: 'Imprimer le bon de retour',
                color: AppColors.primary,
                onPressed: _printing ? null : _print,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ],
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...ret.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSale ? AppColors.warning : AppColors.info,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(item.productName,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text(
                    '${_fmtQty(item.quantity)} × ${fmt.format(item.unitPrice)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  Text(fmt.format(item.subtotal),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── New sale return dialog ─────────────────────────────────────────────────

class _NewSaleReturnDialog extends ConsumerStatefulWidget {
  final Future<bool> Function(
      String saleId,
      List<Map<String, dynamic>> items,
      double refundAmount,
      String? reason) onSubmit;

  const _NewSaleReturnDialog({required this.onSubmit});

  @override
  ConsumerState<_NewSaleReturnDialog> createState() =>
      _NewSaleReturnDialogState();
}

class _NewSaleReturnDialogState extends ConsumerState<_NewSaleReturnDialog> {
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _refundCtrl = TextEditingController();
  final _repo = ReturnRepository();

  bool _searching = false;
  bool _submitting = false;
  bool _printing = false;
  bool _submitted = false;
  String? _searchError;

  SaleModel? _sale;
  ReturnModel? _localReturn;

  // qty controllers per item index
  final Map<int, TextEditingController> _qtyCtrls = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    _refundCtrl.dispose();
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _sale = null;
      _qtyCtrls.clear();
    });
    try {
      final res = await _repo.searchSales(q);
      if (res.data.isEmpty) {
        setState(() => _searchError = 'Aucune vente trouvée pour "$q"');
      } else {
        final sale = res.data.first;
        final ctrls = <int, TextEditingController>{};
        for (var i = 0; i < sale.items.length; i++) {
          ctrls[i] = TextEditingController(text: '0');
        }
        setState(() {
          _sale = sale;
          _qtyCtrls.addAll(ctrls);
          _refundCtrl.text = '0';
        });
      }
    } catch (e) {
      setState(() => _searchError = 'Erreur : $e');
    } finally {
      setState(() => _searching = false);
    }
  }

  double get _computedRefund {
    if (_sale == null) return 0;
    double total = 0;
    for (var i = 0; i < _sale!.items.length; i++) {
      final qty = double.tryParse(_qtyCtrls[i]?.text ?? '0') ?? 0;
      total += qty * _sale!.items[i].unitPrice;
    }
    return total;
  }

  void _updateRefund() {
    _refundCtrl.text = _computedRefund.toStringAsFixed(2);
  }

  List<Map<String, dynamic>> get _selectedItems {
    if (_sale == null) return [];
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < _sale!.items.length; i++) {
      final qty = double.tryParse(_qtyCtrls[i]?.text ?? '0') ?? 0;
      if (qty > 0 && _sale!.items[i].productId != null) {
        result.add({
          'product_id': _sale!.items[i].productId,
          'quantity': qty,
        });
      }
    }
    return result;
  }

  bool get _canSubmit =>
      _sale != null && _selectedItems.isNotEmpty && !_submitting;

  ReturnModel _buildLocalReturn() {
    final refund = double.tryParse(_refundCtrl.text) ?? _computedRefund;
    final items = <ReturnItemModel>[];
    for (var i = 0; i < _sale!.items.length; i++) {
      final qty = double.tryParse(_qtyCtrls[i]?.text ?? '0') ?? 0;
      if (qty > 0) {
        final si = _sale!.items[i];
        items.add(ReturnItemModel(
          productName: si.productName ?? 'Produit',
          quantity: qty,
          unitPrice: si.unitPrice,
          subtotal: qty * si.unitPrice,
        ));
      }
    }
    return ReturnModel(
      id: '',
      returnType: 'sale',
      docReference: _sale!.reference,
      totalReturned: _computedRefund,
      refundAmount: refund,
      reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      createdAt: DateTime.now(),
      items: items,
    );
  }

  Future<void> _submit() async {
    final items = _selectedItems;
    if (items.isEmpty) return;
    final local = _buildLocalReturn();
    setState(() => _submitting = true);
    final ok = await widget.onSubmit(
      _sale!.id,
      items,
      double.tryParse(_refundCtrl.text) ?? _computedRefund,
      _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
    );
    if (mounted) {
      setState(() {
        _submitting = false;
        if (ok) {
          _submitted = true;
          _localReturn = local;
        }
      });
    }
  }

  Future<void> _printReturn() async {
    final ret = _localReturn;
    if (ret == null) return;
    setState(() => _printing = true);
    try {
      final settings = ref.read(settingsProvider);
      final bytes = await buildReturnPdf(ret, settings);
      if (settings.docPrinterName.isNotEmpty) {
        final printers = await Printing.listPrinters();
        final printer = printers.cast<Printer?>().firstWhere(
          (p) => p?.url == settings.docPrinterName,
          orElse: () => null,
        );
        if (printer != null) {
          await Printing.directPrintPdf(
            printer: printer,
            onLayout: (_) => bytes,
            name: 'Retour_${ret.docReference}',
          );
          return;
        }
      }
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'Retour_${ret.docReference}',
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 740),
        child: Column(
          children: [
            // Header
            _DialogHeader(
              icon: Icons.assignment_return_rounded,
              title: 'Retour client',
              color: AppColors.warning,
            ),

            // Body
            if (_submitted && _localReturn != null)
              _ReceiptPhase(
                ret: _localReturn!,
                printing: _printing,
                onPrint: _printReturn,
                onClose: () => Navigator.pop(context, true),
              )
            else ...[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Référence de la vente (ex: VNT-XXXXX)',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _search(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _searching ? null : _search,
                          child: _searching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Chercher'),
                        ),
                      ]),

                      if (_searchError != null) ...[
                        const SizedBox(height: 8),
                        _ErrorText(_searchError!),
                      ],

                      if (_sale != null) ...[
                        const SizedBox(height: 16),
                        _SaleInfoBanner(sale: _sale!),
                        const SizedBox(height: 16),
                        const Text('Articles à retourner',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 8),
                        ..._sale!.items.asMap().entries.map((e) {
                          final i = e.key;
                          final item = e.value;
                          final maxQty = item.quantity;
                          final ctrl = _qtyCtrls[i]!;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.productName ?? 'Produit',
                                        style: const TextStyle(fontSize: 13)),
                                    Text(
                                      'Vendu : ${_fmtQty(maxQty)} — Prix : ${item.unitPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: ctrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    labelText: 'Qté retour',
                                    isDense: true,
                                    helperText: 'max ${_fmtQty(maxQty)}',
                                  ),
                                  onChanged: (_) {
                                    final qty =
                                        double.tryParse(ctrl.text) ?? 0;
                                    if (qty > maxQty) {
                                      ctrl.text = _fmtQty(maxQty);
                                    }
                                    setState(_updateRefund);
                                  },
                                ),
                              ),
                            ]),
                          );
                        }),

                        const Divider(height: 24),

                        // Refund amount
                        Row(children: [
                          const Expanded(
                            child: Text('Montant remboursé',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                          SizedBox(
                            width: 130,
                            child: TextField(
                              controller: _refundCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),

                        // Reason
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
                      ],
                    ],
                  ),
                ),
              ),

              // Footer
              _DialogFooter(
                onCancel: () => Navigator.pop(context),
                onConfirm: _canSubmit ? _submit : null,
                submitting: _submitting,
                confirmLabel: 'Enregistrer le retour',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── New purchase return dialog ─────────────────────────────────────────────

class _NewPurchaseReturnDialog extends StatefulWidget {
  final Future<void> Function(
      String purchaseId,
      List<Map<String, dynamic>> items,
      String? reason) onSubmit;

  const _NewPurchaseReturnDialog({required this.onSubmit});

  @override
  State<_NewPurchaseReturnDialog> createState() =>
      _NewPurchaseReturnDialogState();
}

class _NewPurchaseReturnDialogState
    extends State<_NewPurchaseReturnDialog> {
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _repo = ReturnRepository();

  bool _searching = false;
  bool _submitting = false;
  String? _searchError;

  PurchaseModel? _purchase;
  final Map<int, TextEditingController> _qtyCtrls = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _purchase = null;
      _qtyCtrls.clear();
    });
    try {
      final res = await _repo.searchPurchases(q);
      if (res.data.isEmpty) {
        setState(() => _searchError = 'Aucun achat trouvé pour "$q"');
      } else {
        final purchase = res.data.first;
        final ctrls = <int, TextEditingController>{};
        for (var i = 0; i < purchase.items.length; i++) {
          ctrls[i] = TextEditingController(text: '0');
        }
        setState(() {
          _purchase = purchase;
          _qtyCtrls.addAll(ctrls);
        });
      }
    } catch (e) {
      setState(() => _searchError = 'Erreur : $e');
    } finally {
      setState(() => _searching = false);
    }
  }

  List<Map<String, dynamic>> get _selectedItems {
    if (_purchase == null) return [];
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < _purchase!.items.length; i++) {
      final qty = double.tryParse(_qtyCtrls[i]?.text ?? '0') ?? 0;
      if (qty > 0) {
        result.add({
          'product_id': _purchase!.items[i].productId,
          'quantity': qty,
        });
      }
    }
    return result;
  }

  bool get _canSubmit =>
      _purchase != null && _selectedItems.isNotEmpty && !_submitting;

  Future<void> _submit() async {
    final items = _selectedItems;
    if (items.isEmpty) return;
    setState(() => _submitting = true);
    await widget.onSubmit(
      _purchase!.id,
      items,
      _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          children: [
            _DialogHeader(
              icon: Icons.undo_rounded,
              title: 'Retour fournisseur',
              color: AppColors.info,
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'Référence de l\'achat (ex: ACH-XXXXX)',
                            prefixIcon: Icon(Icons.search_rounded),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _searching ? null : _search,
                        child: _searching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Chercher'),
                      ),
                    ]),

                    if (_searchError != null) ...[
                      const SizedBox(height: 8),
                      _ErrorText(_searchError!),
                    ],

                    if (_purchase != null) ...[
                      const SizedBox(height: 16),
                      _PurchaseInfoBanner(purchase: _purchase!),
                      const SizedBox(height: 16),
                      const Text('Articles à retourner',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      ..._purchase!.items.asMap().entries.map((e) {
                        final i = e.key;
                        final item = e.value;
                        final maxQty = item.orderedQty;
                        final ctrl = _qtyCtrls[i]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName ?? 'Produit',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  Text(
                                    'Acheté : ${_fmtQty(maxQty)} — Prix : ${item.unitPrice.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: ctrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  labelText: 'Qté retour',
                                  isDense: true,
                                  helperText: 'max ${_fmtQty(maxQty)}',
                                ),
                                onChanged: (_) {
                                  final qty =
                                      double.tryParse(ctrl.text) ?? 0;
                                  if (qty > maxQty) {
                                    ctrl.text = _fmtQty(maxQty);
                                  }
                                  setState(() {});
                                },
                              ),
                            ),
                          ]),
                        );
                      }),

                      const Divider(height: 24),

                      // Reason
                      TextField(
                        controller: _reasonCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Motif du retour (optionnel)',
                          hintText:
                              'Ex: Produit endommagé, Erreur de livraison...',
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            _DialogFooter(
              onCancel: () => Navigator.pop(context),
              onConfirm: _canSubmit ? _submit : null,
              submitting: _submitting,
              confirmLabel: 'Enregistrer le retour',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Receipt phase (shown after successful return creation) ─────────────────

class _ReceiptPhase extends StatelessWidget {
  final ReturnModel ret;
  final bool printing;
  final VoidCallback onPrint;
  final VoidCallback onClose;

  const _ReceiptPhase({
    required this.ret,
    required this.printing,
    required this.onPrint,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'fr_HT', symbol: '', decimalDigits: 2);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('Retour client enregistré',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Réf: ${ret.docReference}  •  ${ret.items.length} article(s)',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            if (ret.refundAmount > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Remboursé : ${fmt.format(ret.refundAmount)}',
                style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
            ],
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: printing ? null : onPrint,
                  icon: printing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print_rounded, size: 16),
                  label: const Text('Imprimer le bon de retour'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Fermer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _DialogHeader(
      {required this.icon, required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }
}

class _DialogFooter extends StatelessWidget {
  final VoidCallback? onConfirm;
  final VoidCallback onCancel;
  final bool submitting;
  final String confirmLabel;

  const _DialogFooter({
    required this.onConfirm,
    required this.onCancel,
    required this.submitting,
    required this.confirmLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: onCancel, child: const Text('Annuler')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onConfirm,
            icon: submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}

class _SaleInfoBanner extends StatelessWidget {
  final SaleModel sale;
  const _SaleInfoBanner({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.receipt_rounded,
            color: AppColors.warning, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${sale.reference}  •  ${sale.customerName ?? 'Client comptoir'}  '
            '•  ${_dateFmt.format(sale.createdAt)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }
}

class _PurchaseInfoBanner extends StatelessWidget {
  final PurchaseModel purchase;
  const _PurchaseInfoBanner({required this.purchase});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.shopping_cart_rounded,
            color: AppColors.info, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${purchase.reference}  •  ${purchase.supplierName ?? 'Fournisseur'}  '
            '•  ${_dateFmt.format(purchase.createdAt)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String message;
  const _ErrorText(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: Text(message,
                style: const TextStyle(
                    color: AppColors.error, fontSize: 13))),
      ]),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(message,
              style:
                  const TextStyle(color: AppColors.error, fontSize: 14)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
