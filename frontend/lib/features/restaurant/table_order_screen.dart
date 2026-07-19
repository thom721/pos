import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';
import 'package:pos_connect/providers/restaurant_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';

class TableOrderScreen extends ConsumerStatefulWidget {
  final String tableId;
  const TableOrderScreen({super.key, required this.tableId});

  @override
  ConsumerState<TableOrderScreen> createState() => _TableOrderScreenState();
}

class _TableOrderScreenState extends ConsumerState<TableOrderScreen> {
  RestaurantOrderModel? _order;
  bool _loading = true;
  bool _submitting = false;
  final _searchCtrl = TextEditingController();
  List<ProductModel> _searchResults = [];
  bool _searching = false;

  final _repo = RestaurantRepository();
  final _fmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    setState(() => _loading = true);
    try {
      _order = await _repo.getTableOrder(widget.tableId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openOrder() async {
    setState(() => _submitting = true);
    try {
      _order = await _repo.openOrder(widget.tableId);
      ref.invalidate(tablesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _addItem(ProductModel product, {String? notes}) async {
    if (_order == null) return;
    setState(() => _submitting = true);
    try {
      _order = await _repo.addItem(_order!.id, productId: product.id, notes: notes);
      _searchCtrl.clear();
      setState(() => _searchResults = []);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _removeItem(String itemId) async {
    if (_order == null) return;
    setState(() => _submitting = true);
    try {
      await _repo.removeItem(_order!.id, itemId);
      _order = await _repo.getTableOrder(widget.tableId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _sendToKitchen() async {
    if (_order == null || _order!.items.isEmpty) return;
    setState(() => _submitting = true);
    try {
      _order = await _repo.sendToKitchen(_order!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Commande envoyée en cuisine'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _checkout() async {
    if (_order == null || _order!.items.isEmpty) return;
    final settings = ref.read(settingsProvider);
    final symbol = settings.currencySymbol;
    final total = _order!.total;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CheckoutDialog(total: total, symbol: symbol),
    );
    if (result == null) return;

    setState(() => _submitting = true);
    try {
      final data = await _repo.checkout(
        _order!.id,
        paidAmount: result['paid'] as double,
        paymentMethod: result['method'] as String,
        discount: result['discount'] as double,
      );
      ref.invalidate(tablesProvider);
      if (mounted) {
        final change = (data['change'] as num?)?.toDouble() ?? 0.0;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Paiement reçu'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
                const SizedBox(height: 12),
                Text('Réf: ${data['reference']}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (change > 0) ...[
                  const SizedBox(height: 8),
                  Text('Monnaie à rendre : $symbol${_fmt.format(change)}',
                      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Terminer'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final symbol = settings.currencySymbol;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: _loading
            ? const Text('Chargement…')
            : Text(
                _order?.tableName ?? 'Table',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
        actions: [
          if (_order != null && _order!.status != 'closed')
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
              onPressed: _loadOrder,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _order == null
              ? _NoOrderView(onOpen: _openOrder, submitting: _submitting)
              : Column(
                  children: [
                    // Statut de la commande
                    if (_order!.sentToKitchen || _order!.isReady)
                      _StatusBanner(status: _order!.status),

                    // Recherche produit
                    _ProductSearch(
                      controller: _searchCtrl,
                      results: _searchResults,
                      searching: _searching,
                      onSearch: _onSearch,
                      onAdd: _addItem,
                    ),

                    // Liste des articles
                    Expanded(
                      child: _order!.items.isEmpty
                          ? const Center(
                              child: Text('Aucun article — cherchez un plat ci-dessus',
                                  style: TextStyle(color: AppColors.textSecondary)))
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _order!.items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _OrderItemTile(
                                item: _order!.items[i],
                                symbol: symbol,
                                onRemove: () => _removeItem(_order!.items[i].id),
                              ),
                            ),
                    ),

                    // Total + actions
                    _BottomBar(
                      order: _order!,
                      symbol: symbol,
                      submitting: _submitting,
                      onKitchen: _sendToKitchen,
                      onCheckout: _checkout,
                    ),
                  ],
                ),
    );
  }

  Future<void> _onSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await ref.read(restaurantRepositoryProvider).searchProducts(query);
      if (mounted) setState(() => _searchResults = res);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }
}

// ── Sous-widgets ─────────────────────────────────────────────────────────────

class _NoOrderView extends StatelessWidget {
  final VoidCallback onOpen;
  final bool submitting;
  const _NoOrderView({required this.onOpen, required this.submitting});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_rounded, size: 64, color: AppColors.divider),
          const SizedBox(height: 16),
          const Text('Aucune commande ouverte pour cette table',
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: submitting ? null : onOpen,
            icon: submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_rounded),
            label: const Text('Ouvrir une commande'),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final isReady = status == 'ready';
    final color = isReady ? AppColors.success : AppColors.warning;
    final icon  = isReady ? Icons.check_circle_rounded : Icons.restaurant_rounded;
    final label = isReady ? 'Commande prête à servir' : 'En cuisine…';

    return Container(
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ProductSearch extends StatelessWidget {
  final TextEditingController controller;
  final List<ProductModel> results;
  final bool searching;
  final void Function(String) onSearch;
  final void Function(ProductModel, {String? notes}) onAdd;

  const _ProductSearch({
    required this.controller,
    required this.results,
    required this.searching,
    required this.onSearch,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: controller,
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Chercher un plat…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () { controller.clear(); onSearch(''); },
                        )
                      : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        if (results.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (_, i) {
                final p = results[i];
                return ListTile(
                  dense: true,
                  title: Text(p.name),
                  trailing: Text(p.salePrice.toStringAsFixed(0),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  onTap: () => onAdd(p),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _OrderItemTile extends StatelessWidget {
  final RestaurantOrderItemModel item;
  final String symbol;
  final VoidCallback onRemove;

  const _OrderItemTile({required this.item, required this.symbol, required this.onRemove});

  Color get _statusColor {
    if (item.status == 'ready') return AppColors.success;
    if (item.status == 'preparing') return AppColors.warning;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 1)}x',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Text(item.notes!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
                    ),
                    Text(
                      item.status == 'ready' ? 'Prêt' : item.status == 'preparing' ? 'En préparation' : 'En attente',
                      style: TextStyle(fontSize: 11, color: _statusColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text('$symbol${NumberFormat('#,##0.00').format(item.subtotal)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error, size: 20),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final RestaurantOrderModel order;
  final String symbol;
  final bool submitting;
  final VoidCallback onKitchen;
  final VoidCallback onCheckout;

  const _BottomBar({
    required this.order,
    required this.symbol,
    required this.submitting,
    required this.onKitchen,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              Text('$symbol${NumberFormat('#,##0.00').format(order.total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!order.sentToKitchen && !order.isReady)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: submitting || order.items.isEmpty ? null : onKitchen,
                    icon: const Icon(Icons.restaurant_rounded),
                    label: const Text('Envoyer en cuisine'),
                  ),
                ),
              if (!order.sentToKitchen && !order.isReady) const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: submitting || order.items.isEmpty ? null : onCheckout,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  icon: submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.point_of_sale_rounded),
                  label: const Text('Encaisser'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckoutDialog extends StatefulWidget {
  final double total;
  final String symbol;
  const _CheckoutDialog({required this.total, required this.symbol});

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  final _paidCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  String _method = 'CASH';

  double get _discount => double.tryParse(_discountCtrl.text) ?? 0.0;
  double get _finalAmount => (widget.total - _discount).clamp(0, double.infinity);
  double get _paid => double.tryParse(_paidCtrl.text) ?? 0.0;
  double get _change => (_paid - _finalAmount).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    _paidCtrl.text = widget.total.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return AlertDialog(
      title: const Text('Encaissement'),
      content: StatefulBuilder(
        builder: (_, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Méthode de paiement
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'CASH', label: Text('Espèces'), icon: Icon(Icons.payments_rounded)),
                ButtonSegment(value: 'CARD', label: Text('Carte'), icon: Icon(Icons.credit_card_rounded)),
                ButtonSegment(value: 'TRANSFER', label: Text('Virement'), icon: Icon(Icons.account_balance_rounded)),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Remise',
                prefixText: widget.symbol,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total net :'),
                Text('${widget.symbol}${fmt.format(_finalAmount)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _paidCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Montant reçu',
                prefixText: widget.symbol,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_change > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Monnaie à rendre :'),
                    Text('${widget.symbol}${fmt.format(_change)}',
                        style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _paid >= _finalAmount
              ? () => Navigator.pop(context, {'paid': _paid, 'method': _method, 'discount': _discount})
              : null,
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}
