import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/purchase_model.dart';
import 'package:pos_connect/data/models/supplier_model.dart';
import 'package:pos_connect/data/repositories/purchase_repository.dart';
import 'package:pos_connect/providers/purchase_provider.dart';
import 'package:pos_connect/providers/supplier_provider.dart';
import 'package:pos_connect/providers/product_provider.dart';
import 'package:pos_connect/shared/widgets/status_badge.dart';

final _fmt =
    NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  final _searchCtrl = TextEditingController();
  String? _statusFilter;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchasesProvider);

    return Column(
      children: [
        Container(
          color: AppColors.surface,
          padding: EdgeInsets.all(context.hPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Rechercher par référence ou fournisseur...',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                      ),
                      onChanged: (v) => _update(search: v),
                    ),
                  ),
                  if (!context.isMobile) ...[
                    const SizedBox(width: 12),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _statusFilter,
                        hint: const Text('Statut'),
                        borderRadius: BorderRadius.circular(8),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Tous')),
                          DropdownMenuItem(value: 'paid', child: Text('Payé')),
                          DropdownMenuItem(value: 'partial', child: Text('Partiel')),
                          DropdownMenuItem(value: 'pending', child: Text('En attente')),
                        ],
                        onChanged: (v) {
                          setState(() => _statusFilter = v);
                          _update(status: v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Nouvel achat'),
                    ),
                  ],
                ],
              ),
              if (context.isMobile) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _statusFilter,
                          isExpanded: true,
                          hint: const Text('Filtrer par statut'),
                          borderRadius: BorderRadius.circular(8),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Tous les statuts')),
                            DropdownMenuItem(value: 'paid', child: Text('Payé')),
                            DropdownMenuItem(value: 'partial', child: Text('Partiel')),
                            DropdownMenuItem(value: 'pending', child: Text('En attente')),
                          ],
                          onChanged: (v) {
                            setState(() => _statusFilter = v);
                            _update(status: v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Nouvel achat'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: purchasesAsync.when(
            data: (purchases) => purchases.data.isEmpty
                ? const Center(
                    child: Text('Aucun achat trouvé',
                        style:
                            TextStyle(color: AppColors.textSecondary)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: purchases.data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _PurchaseCard(purchase: purchases.data[i]),
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

  void _update({String? search, String? status}) {
    ref.read(purchaseListParamsProvider.notifier).state =
        PurchaseListParams(
      page: 1,
      search: search ?? _searchCtrl.text,
      status: status ?? _statusFilter,
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _CreatePurchaseDialog(),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  final PurchaseModel purchase;

  const _PurchaseCard({required this.purchase});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.shopping_cart_rounded,
              color: AppColors.warning, size: 22),
        ),
        title: Text(purchase.reference,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
          '${purchase.supplierName ?? 'Fournisseur'} • ${_dateFmt.format(purchase.createdAt)}',
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_fmt.format(purchase.totalAmount),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            StatusBadge(status: purchase.status),
          ],
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...purchase.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.productName ?? 'Produit',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text(
                      '${item.orderedQty.toStringAsFixed(0)} × ${_fmt.format(item.unitPrice)}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Text(_fmt.format(item.subtotal),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Total: ${_fmt.format(purchase.totalAmount)}  ',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Text('Payé: ${_fmt.format(purchase.paidAmount)}',
                  style: TextStyle(
                      color: purchase.balance > 0
                          ? AppColors.error
                          : AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Create purchase dialog ──────────────────────────────────────────────────
class _CreatePurchaseDialog extends ConsumerStatefulWidget {
  const _CreatePurchaseDialog();

  @override
  ConsumerState<_CreatePurchaseDialog> createState() =>
      _CreatePurchaseDialogState();
}

class _CreatePurchaseDialogState
    extends ConsumerState<_CreatePurchaseDialog> {
  final _paidCtrl = TextEditingController(text: '0');
  SupplierModel? _supplier;
  final _items = <Map<String, dynamic>>[];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _paidCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersProvider);
    final productsAsync = ref.watch(productsProvider);

    return AlertDialog(
      title: const Text('Nouvel achat fournisseur'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Supplier
              suppliersAsync.when(
                data: (suppliers) => DropdownButtonFormField<SupplierModel>(
                  value: _supplier,
                  decoration:
                      const InputDecoration(labelText: 'Fournisseur *'),
                  items: suppliers.data
                      .map((s) => DropdownMenuItem(
                          value: s, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _supplier = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Erreur chargement fournisseurs'),
              ),
              const SizedBox(height: 16),

              // Items
              Text('Articles',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              ..._items.asMap().entries.map((e) => _ItemRow(
                    item: e.value,
                    products: productsAsync.asData?.value.data ?? [],
                    onRemove: () =>
                        setState(() => _items.removeAt(e.key)),
                    onUpdate: (updated) => setState(
                        () => _items[e.key] = updated),
                  )),
              TextButton.icon(
                onPressed: () => setState(() => _items.add({
                      'product_id': null,
                      'ordered_qty': 1.0,
                      'remaining_qty': 1.0,
                      'unit_price': 0.0,
                    })),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ajouter un article'),
              ),
              const SizedBox(height: 12),

              // Paid amount
              TextField(
                controller: _paidCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant versé (HTG)'),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_supplier == null) {
      setState(() => _error = 'Sélectionnez un fournisseur');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _error = 'Ajoutez au moins un article');
      return;
    }
    if (_items.any((i) => i['product_id'] == null)) {
      setState(() => _error = 'Sélectionnez un produit pour chaque article');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await PurchaseRepository().createPurchase({
        'supplier_id': _supplier!.id,
        'paid_amount': double.tryParse(_paidCtrl.text) ?? 0,
        'items': _items,
      });
      ref.invalidate(purchasesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Erreur lors de la création. Réessayez.';
      });
    }
  }
}

class _ItemRow extends StatefulWidget {
  final Map<String, dynamic> item;
  final List products;
  final VoidCallback onRemove;
  final void Function(Map<String, dynamic>) onUpdate;

  const _ItemRow({
    required this.item,
    required this.products,
    required this.onRemove,
    required this.onUpdate,
  });

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(
        text: widget.item['ordered_qty'].toString());
    _priceCtrl = TextEditingController(
        text: widget.item['unit_price'].toString());
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productDropdown = DropdownButtonFormField<String>(
      value: widget.item['product_id'],
      decoration: const InputDecoration(hintText: 'Produit', isDense: true),
      items: widget.products
          .map<DropdownMenuItem<String>>((p) => DropdownMenuItem(
              value: p.id,
              child: Text(p.name, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (v) {
        final updated = Map<String, dynamic>.from(widget.item);
        updated['product_id'] = v;
        widget.onUpdate(updated);
      },
    );

    final qtyField = SizedBox(
      width: 60,
      child: TextField(
        controller: _qtyCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(hintText: 'Qté', isDense: true),
        onChanged: (v) {
          final updated = Map<String, dynamic>.from(widget.item);
          updated['ordered_qty'] = double.tryParse(v) ?? 1;
          updated['remaining_qty'] = updated['ordered_qty'];
          widget.onUpdate(updated);
        },
      ),
    );

    final priceField = Expanded(
      child: TextField(
        controller: _priceCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(hintText: 'Prix (HTG)', isDense: true),
        onChanged: (v) {
          final updated = Map<String, dynamic>.from(widget.item);
          updated['unit_price'] = double.tryParse(v) ?? 0;
          widget.onUpdate(updated);
        },
      ),
    );

    final removeBtn = IconButton(
      icon: const Icon(Icons.remove_circle_outline,
          color: AppColors.error, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: widget.onRemove,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: context.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                productDropdown,
                const SizedBox(height: 6),
                Row(children: [
                  qtyField,
                  const SizedBox(width: 8),
                  priceField,
                  removeBtn,
                ]),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: productDropdown),
                const SizedBox(width: 6),
                qtyField,
                const SizedBox(width: 6),
                priceField,
                removeBtn,
              ],
            ),
    );
  }
}
