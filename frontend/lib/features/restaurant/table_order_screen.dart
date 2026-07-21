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
  final RestaurantTableModel? table;
  const TableOrderScreen({super.key, required this.tableId, this.table});

  @override
  ConsumerState<TableOrderScreen> createState() => _TableOrderScreenState();
}

class _TableOrderScreenState extends ConsumerState<TableOrderScreen> {
  RestaurantOrderModel? _order;
  bool _loading = true;
  bool _submitting = false;
  final _searchCtrl = TextEditingController();
  List<_SearchResult> _searchResults = [];
  bool _searching = false;

  RestaurantTableModel? _table;
  List<MenuItemModel> _allMenuItems = [];
  bool _menuItemsLoaded = false;

  final _repo = RestaurantRepository();
  final _fmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _table = widget.table;
    _loadOrder();
    _loadMenuItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMenuItems() async {
    if (_menuItemsLoaded) return;
    try {
      _allMenuItems = await _repo.getMenuItems(availableOnly: true);
      if (mounted) setState(() => _menuItemsLoaded = true);
    } catch (_) {}
  }

  Future<void> _loadOrder() async {
    setState(() => _loading = true);
    try {
      _order = await _repo.getTableOrder(widget.tableId);
      if (_table == null) {
        final tables = await _repo.getTables();
        _table = tables.where((t) => t.id == widget.tableId).firstOrNull;
      }
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

  bool get _isRoom =>
      _table != null &&
      (_table!.price > 0 ||
          _table!.pricePerDay > 0 ||
          _table!.pricePerMoment > 0 ||
          _table!.attributes.isNotEmpty);

  Future<void> _confirmOpen() async {
    final isHotel = ref.read(settingsProvider).businessType == 'hotel';
    if (isHotel && _isRoom) {
      await _confirmHotelCheckIn();
    } else {
      await _confirmRestaurantOpen();
    }
  }

  Future<void> _confirmRestaurantOpen() async {
    int covers = 2;
    final confirmed = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Ouvrir une commande'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Couverts : ', style: TextStyle(fontSize: 15)),
              IconButton(
                icon: const Icon(Icons.remove_rounded),
                onPressed: () => setState(() { if (covers > 1) covers--; }),
              ),
              Text('$covers', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => setState(() => covers++),
              ),
              const Icon(Icons.people_outline_rounded, color: AppColors.textSecondary),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, covers),
              child: const Text('Ouvrir'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == null) return;
    await _openOrder(covers: confirmed);
  }

  Future<void> _confirmHotelCheckIn() async {
    final table = _table!;
    final today = DateTime.now();
    DateTime checkOut = today.add(const Duration(days: 1));
    final guestCtrl = TextEditingController();
    String rateType = table.price > 0 ? 'nuit' : (table.pricePerDay > 0 ? 'jour' : 'moment');

    double rateValue(String type) {
      if (type == 'nuit') return table.price;
      if (type == 'jour') return table.pricePerDay;
      return table.pricePerMoment;
    }

    String? error;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final nights = checkOut
              .difference(DateTime(today.year, today.month, today.day))
              .inDays
              .clamp(1, 365);
          final rate = rateValue(rateType);
          final total = nights * rate;

          return AlertDialog(
            title: Row(children: [
              const Icon(Icons.king_bed_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Text('Check-in — ${table.name}'),
            ]),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: guestCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Nom du client *',
                        prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                        errorText: error,
                      ),
                      onChanged: (_) => setInner(() => error = null),
                    ),
                    const SizedBox(height: 16),
                    // Check-in / Check-out
                    Row(children: [
                      Expanded(child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: today,
                            firstDate: today.subtract(const Duration(days: 1)),
                            lastDate: today.add(const Duration(days: 365)),
                          );
                          if (d != null && d.isBefore(checkOut)) setInner(() {});
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Arrivée',
                            prefixIcon: Icon(Icons.login_rounded, size: 18),
                          ),
                          child: Text(DateFormat('dd/MM/yyyy').format(today)),
                        ),
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: checkOut,
                            firstDate: today.add(const Duration(days: 1)),
                            lastDate: today.add(const Duration(days: 365)),
                          );
                          if (d != null) setInner(() => checkOut = d);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Départ',
                            prefixIcon: Icon(Icons.logout_rounded, size: 18),
                          ),
                          child: Text(DateFormat('dd/MM/yyyy').format(checkOut)),
                        ),
                      )),
                    ]),
                    const SizedBox(height: 16),
                    // Tarif selection
                    if (table.price > 0 || table.pricePerDay > 0 || table.pricePerMoment > 0) ...[
                      const Text('Tarif',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, children: [
                        if (table.price > 0) ChoiceChip(
                          label: Text('${NumberFormat('#,##0').format(table.price)} HTG/nuit'),
                          selected: rateType == 'nuit',
                          onSelected: (v) { if (v) setInner(() => rateType = 'nuit'); },
                        ),
                        if (table.pricePerDay > 0) ChoiceChip(
                          label: Text('${NumberFormat('#,##0').format(table.pricePerDay)} HTG/jour'),
                          selected: rateType == 'jour',
                          onSelected: (v) { if (v) setInner(() => rateType = 'jour'); },
                        ),
                        if (table.pricePerMoment > 0) ChoiceChip(
                          label: Text(
                              '${NumberFormat('#,##0').format(table.pricePerMoment)} HTG/moment'),
                          selected: rateType == 'moment',
                          onSelected: (v) { if (v) setInner(() => rateType = 'moment'); },
                        ),
                      ]),
                    ],
                    const SizedBox(height: 16),
                    // Summary
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$nights $rateType(s) × ${NumberFormat('#,##0').format(rate)} HTG',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                          Text(
                            '${NumberFormat('#,##0.00').format(total)} HTG',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Check-in'),
                onPressed: () {
                  final name = guestCtrl.text.trim();
                  if (name.isEmpty) {
                    setInner(() => error = 'Nom requis');
                    return;
                  }
                  final nights = checkOut
                      .difference(DateTime(today.year, today.month, today.day))
                      .inDays
                      .clamp(1, 365);
                  Navigator.pop(ctx, {
                    'name': name,
                    'checkin': today,
                    'checkout': checkOut,
                    'nights': nights,
                    'rate': rateValue(rateType),
                    'rate_type': rateType,
                  });
                },
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    setState(() => _submitting = true);
    try {
      final fmt = DateFormat('dd/MM/yyyy');
      _order = await _repo.openOrder(
        tableId: widget.tableId,
        covers: 1,
        notes:
            '🏨 ${result['name']} | ${fmt.format(result['checkin'] as DateTime)} → ${fmt.format(result['checkout'] as DateTime)}',
      );
      ref.invalidate(tablesProvider);
      // Add room charge as first item
      final n = result['nights'] as int;
      final r = result['rate'] as double;
      final rt = result['rate_type'] as String;
      final label =
          'Séjour chambre — $n $rt(s) × ${NumberFormat('#,##0.00').format(r)} HTG';
      _order = await _repo.addItem(_order!.id,
          label: label, quantity: n.toDouble(), unitPrice: r);
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

  Future<void> _openOrder({int covers = 2}) async {
    setState(() => _submitting = true);
    try {
      _order = await _repo.openOrder(tableId: widget.tableId, covers: covers);
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

  Future<void> _addProduct(ProductModel product) async {
    if (_order == null) return;
    setState(() => _submitting = true);
    try {
      _order = await _repo.addItem(_order!.id, productId: product.id);
      _searchCtrl.clear();
      if (mounted) setState(() => _searchResults = []);
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

  Future<void> _addMenuItem(MenuItemModel item) async {
    if (_order == null) return;
    double unitPrice = item.price;
    String? variantNote;

    if (item.hasVariants) {
      final picked = await _pickVariant(item);
      if (picked == null) return; // cancelled
      unitPrice = picked['price'] as double;
      variantNote = picked['name'] as String;
    }

    setState(() => _submitting = true);
    try {
      _order = await _repo.addItem(_order!.id,
          menuItemId: item.id,
          unitPrice: unitPrice,
          notes: variantNote);
      _searchCtrl.clear();
      if (mounted) setState(() => _searchResults = []);
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

  Future<Map<String, dynamic>?> _pickVariant(MenuItemModel item) {
    final rows =
        item.variantRows.where((r) => r['available'] as bool? ?? true).toList();
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Variante — ${item.name}'),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: SizedBox(
          width: 320,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final row = rows[i];
              final name = row['name']?.toString() ?? 'Variante ${i + 1}';
              final delta = (row['price_delta'] as num?)?.toDouble() ?? 0;
              final finalPrice = item.price + delta;
              return ListTile(
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                trailing: Text(
                  '${NumberFormat('#,##0.00').format(finalPrice)} HTG',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
                onTap: () =>
                    Navigator.pop(ctx, {'name': name, 'price': finalPrice}),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
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
      builder: (_) =>
          _CheckoutDialog(total: total, symbol: symbol, covers: _order!.covers),
    );
    if (result == null) return;

    setState(() => _submitting = true);
    try {
      final data = await _repo.checkout(
        _order!.id,
        paidAmount: result['paid'] as double,
        paymentMethod: result['method'] as String,
        discount: result['discount'] as double,
        tip: result['tip'] as double,
      );
      ref.invalidate(tablesProvider);
      if (mounted) {
        final change = (data['change'] as num?)?.toDouble() ?? 0.0;
        final tip = (data['tip'] as num?)?.toDouble() ?? 0.0;
        final subtotal = (data['subtotal'] as num?)?.toDouble() ?? 0.0;
        final total = (data['total'] as num?)?.toDouble() ?? 0.0;
        final covers = data['covers'] as int? ?? 1;
        final tableName = data['table_name'] as String? ?? '';
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Paiement reçu'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                    child: Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 56)),
                const SizedBox(height: 12),
                Center(
                  child: Text('Réf: ${data['reference']}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                if (tableName.isNotEmpty) _receiptRow('Table', tableName),
                _receiptRow('Couverts', '$covers'),
                _receiptRow('Sous-total', '$symbol${_fmt.format(subtotal)}'),
                if ((result['discount'] as double) > 0)
                  _receiptRow('Remise',
                      '-$symbol${_fmt.format(result['discount'] as double)}'),
                if (tip > 0)
                  _receiptRow('Pourboire', '+$symbol${_fmt.format(tip)}'),
                const Divider(),
                _receiptRow('Total', '$symbol${_fmt.format(total)}',
                    bold: true),
                if (change > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Monnaie à rendre :'),
                        Text('$symbol${_fmt.format(change)}',
                            style: const TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
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
    final isHotel = settings.businessType == 'hotel';

    final isRoom = isHotel && _isRoom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: _loading
            ? const Text('Chargement…')
            : Text(
                _order?.tableName ?? _table?.name ?? 'Table',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
        actions: [
          if (_order != null && _order!.status != 'closed')
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: AppColors.textSecondary),
              onPressed: _loadOrder,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _order == null
              ? _NoOrderView(
                  onOpen: _confirmOpen,
                  submitting: _submitting,
                  isRoom: isRoom,
                )
              : Column(
                  children: [
                    // Statut de la commande
                    if (_order!.sentToKitchen || _order!.isReady)
                      _StatusBanner(status: _order!.status),

                    // Hotel banner
                    if (_order!.notes != null &&
                        (_order!.notes!.startsWith('🏨')))
                      _HotelBanner(notes: _order!.notes!),

                    // Recherche produit / menu
                    _ProductSearch(
                      controller: _searchCtrl,
                      results: _searchResults,
                      searching: _searching,
                      onSearch: _onSearch,
                      onAdd: (result) {
                        if (result.isMenuItem) {
                          _addMenuItem(result.menuItem!);
                        } else {
                          _addProduct(result.product!);
                        }
                      },
                    ),

                    // Liste des articles
                    Expanded(
                      child: _order!.items.isEmpty
                          ? const Center(
                              child: Text(
                                  'Aucun article — cherchez un plat ci-dessus',
                                  style: TextStyle(
                                      color: AppColors.textSecondary)))
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _order!.items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _OrderItemTile(
                                item: _order!.items[i],
                                symbol: symbol,
                                onRemove: () =>
                                    _removeItem(_order!.items[i].id),
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
                      isRoom: isRoom,
                    ),
                  ],
                ),
    );
  }

  Widget _receiptRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: bold
                        ? AppColors.textPrimary
                        : AppColors.textSecondary)),
            Text(value,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );

  Future<void> _onSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final q = query.toLowerCase();
      final menuResults = _allMenuItems
          .where((m) => m.available && m.name.toLowerCase().contains(q))
          .map(_SearchResult.fromMenuItem)
          .toList();

      final products =
          await ref.read(restaurantRepositoryProvider).searchProducts(query);
      final productResults =
          products.map(_SearchResult.fromProduct).toList();

      if (mounted) {
        setState(() {
          _searchResults = [...menuResults, ...productResults];
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }
}

// ── Search result wrapper ──────────────────────────────────────────────────────

class _SearchResult {
  final ProductModel? product;
  final MenuItemModel? menuItem;
  const _SearchResult._({this.product, this.menuItem});
  factory _SearchResult.fromProduct(ProductModel p) =>
      _SearchResult._(product: p);
  factory _SearchResult.fromMenuItem(MenuItemModel m) =>
      _SearchResult._(menuItem: m);
  String get name => product?.name ?? menuItem?.name ?? '';
  double get price => product?.salePrice ?? menuItem?.price ?? 0;
  bool get isMenuItem => menuItem != null;
}

// ── Sous-widgets ──────────────────────────────────────────────────────────────

class _NoOrderView extends StatelessWidget {
  final VoidCallback onOpen;
  final bool submitting;
  final bool isRoom;
  const _NoOrderView(
      {required this.onOpen,
      required this.submitting,
      this.isRoom = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRoom
                ? Icons.king_bed_outlined
                : Icons.receipt_long_rounded,
            size: 64,
            color: AppColors.divider,
          ),
          const SizedBox(height: 16),
          Text(
            isRoom
                ? 'Aucun séjour en cours pour cette chambre'
                : 'Aucune commande ouverte pour cette table',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: submitting ? null : onOpen,
            icon: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(isRoom
                    ? Icons.login_rounded
                    : Icons.add_rounded),
            label: Text(isRoom ? 'Check-in' : 'Ouvrir une commande'),
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
    final icon =
        isReady ? Icons.check_circle_rounded : Icons.restaurant_rounded;
    final label = isReady ? 'Commande prête à servir' : 'En cuisine…';

    return Container(
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style:
                  TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HotelBanner extends StatelessWidget {
  final String notes;
  const _HotelBanner({required this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.king_bed_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(notes,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _ProductSearch extends StatelessWidget {
  final TextEditingController controller;
  final List<_SearchResult> results;
  final bool searching;
  final void Function(String) onSearch;
  final void Function(_SearchResult) onAdd;

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
              hintText: 'Chercher un plat ou produit…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            controller.clear();
                            onSearch('');
                          },
                        )
                      : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                final r = results[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    r.isMenuItem
                        ? Icons.restaurant_menu_rounded
                        : Icons.inventory_2_rounded,
                    size: 18,
                    color: r.isMenuItem
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  title: Text(r.name),
                  subtitle: Text(
                    r.isMenuItem ? 'MENU' : 'STOCK',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: r.isMenuItem
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  trailing: Text(
                    r.price.toStringAsFixed(0),
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
                  onTap: () => onAdd(r),
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

  const _OrderItemTile(
      {required this.item, required this.symbol, required this.onRemove});

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
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 1)}x',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Text(item.notes!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                          color: _statusColor, shape: BoxShape.circle),
                    ),
                    Text(
                      item.status == 'ready'
                          ? 'Prêt'
                          : item.status == 'preparing'
                              ? 'En préparation'
                              : 'En attente',
                      style:
                          TextStyle(fontSize: 11, color: _statusColor),
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
            icon: const Icon(Icons.remove_circle_outline_rounded,
                color: AppColors.error, size: 20),
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
  final bool isRoom;

  const _BottomBar({
    required this.order,
    required this.symbol,
    required this.submitting,
    required this.onKitchen,
    required this.onCheckout,
    this.isRoom = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 16)),
              Text(
                '$symbol${NumberFormat('#,##0.00').format(order.total)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
                      if (!order.sentToKitchen && !order.isReady)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        submitting || order.items.isEmpty ? null : onKitchen,
                    icon: const Icon(Icons.restaurant_rounded),
                    label: const Text('Envoyer en cuisine'),
                  ),
                ),
              if (!order.sentToKitchen && !order.isReady)
                const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      submitting || order.items.isEmpty ? null : onCheckout,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success),
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(isRoom
                          ? Icons.logout_rounded
                          : Icons.point_of_sale_rounded),
                  label: Text(isRoom ? 'Check-out' : 'Encaisser'),
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
  final int covers;
  const _CheckoutDialog(
      {required this.total, required this.symbol, required this.covers});

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  final _paidCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _tipCtrl = TextEditingController(text: '0');
  String _method = 'CASH';

  double get _discount => double.tryParse(_discountCtrl.text) ?? 0.0;
  double get _tip => double.tryParse(_tipCtrl.text) ?? 0.0;
  double get _finalAmount =>
      (widget.total - _discount + _tip).clamp(0, double.infinity);
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
    _tipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return AlertDialog(
      title: const Text('Encaissement'),
      content: StatefulBuilder(
        builder: (_, setState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_outline_rounded,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                      '${widget.covers} couvert${widget.covers > 1 ? 's' : ''}',
                      style:
                          const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'CASH',
                      label: Text('Espèces'),
                      icon: Icon(Icons.payments_rounded)),
                  ButtonSegment(
                      value: 'CARD',
                      label: Text('Carte'),
                      icon: Icon(Icons.credit_card_rounded)),
                  ButtonSegment(
                      value: 'TRANSFER',
                      label: Text('Virement'),
                      icon: Icon(Icons.account_balance_rounded)),
                ],
                selected: {_method},
                onSelectionChanged: (s) =>
                    setState(() => _method = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _discountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Remise', prefixText: widget.symbol),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tipCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Pourboire',
                  prefixText: widget.symbol,
                  prefixIcon: const Icon(Icons.volunteer_activism_rounded,
                      size: 18),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total net :'),
                  Text('${widget.symbol}${fmt.format(_finalAmount)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _paidCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Montant reçu', prefixText: widget.symbol),
                onChanged: (_) => setState(() {}),
              ),
              if (_change > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Monnaie à rendre :'),
                      Text('${widget.symbol}${fmt.format(_change)}',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _paid >= _finalAmount
              ? () => Navigator.pop(context, {
                    'paid': _paid,
                    'method': _method,
                    'discount': _discount,
                    'tip': _tip,
                  })
              : null,
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}
