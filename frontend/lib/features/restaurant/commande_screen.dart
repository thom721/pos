import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show dio, extractAnyError;
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/product_repository.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';
import 'package:pos_connect/providers/restaurant_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';

final _fmt = NumberFormat('#,##0.00');

class CommandeScreen extends ConsumerStatefulWidget {
  final String orderId;
  const CommandeScreen({super.key, required this.orderId});

  @override
  ConsumerState<CommandeScreen> createState() => _CommandeScreenState();
}

class _CommandeScreenState extends ConsumerState<CommandeScreen>
    with SingleTickerProviderStateMixin {
  RestaurantOrderModel? _order;
  bool _loading = true;
  bool _submitting = false;

  final _repo = RestaurantRepository();
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadOrder();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    setState(() => _loading = true);
    try {
      _order = await _repo.getOrder(widget.orderId);
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

  Future<void> _addItem(MenuItemModel menuItem, {String? notes, double? unitPrice}) async {
    if (_order == null) return;
    setState(() => _submitting = true);
    try {
      _order = await _repo.addItem(_order!.id, menuItemId: menuItem.id, notes: notes, unitPrice: unitPrice);
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
      _order = await _repo.getOrder(widget.orderId);
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

  Future<void> _updateQuantity(String itemId, double newQty) async {
    if (_order == null) return;
    setState(() => _submitting = true);
    try {
      if (newQty <= 0) {
        await _repo.removeItem(_order!.id, itemId);
        _order = await _repo.getOrder(widget.orderId);
      } else {
        _order = await _repo.updateItemQuantity(_order!.id, itemId, newQty);
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

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CheckoutDialog(
        total: _order!.total,
        symbol: symbol,
        covers: _order!.covers,
      ),
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
      ref.invalidate(openOrdersProvider);
      ref.invalidate(tablesProvider);

      if (mounted) {
        final change = (data['change'] as num?)?.toDouble() ?? 0.0;
        final tip = (data['tip'] as num?)?.toDouble() ?? 0.0;
        final subtotal = (data['subtotal'] as num?)?.toDouble() ?? 0.0;
        final total = (data['total'] as num?)?.toDouble() ?? 0.0;
        final covers = data['covers'] as int? ?? 1;
        final tableName = data['table_name'] as String?;

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
                      color: AppColors.success, size: 56),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text('Réf: ${data['reference']}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                _receiptRow('Lieu', tableName ?? 'Comptoir / Bar'),
                _receiptRow('Couverts', '$covers'),
                _receiptRow('Sous-total', '$symbol${_fmt.format(subtotal)}'),
                if ((result['discount'] as double) > 0)
                  _receiptRow('Remise',
                      '-$symbol${_fmt.format(result['discount'] as double)}'),
                if (tip > 0)
                  _receiptRow('Pourboire', '+$symbol${_fmt.format(tip)}'),
                const Divider(),
                _receiptRow('Total', '$symbol${_fmt.format(total)}', bold: true),
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

  Widget _receiptRow(String label, String value, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color:
                        bold ? AppColors.textPrimary : AppColors.textSecondary)),
            Text(value,
                style: TextStyle(
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final symbol = settings.currencySymbol;
    final isWide = MediaQuery.sizeOf(context).width >= 800;

    final tableLabel = _order == null
        ? ''
        : (_order!.hasTable
            ? (_order!.tableName ?? 'Table')
            : 'Comptoir / Bar');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: _loading
            ? const Text('Chargement…')
            : Text(tableLabel,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
        bottom: !isWide && !_loading && _order != null
            ? TabBar(
                controller: _tabCtrl,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.grid_view_rounded, size: 16),
                        const SizedBox(width: 6),
                        const Text('Produits'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Commande (${_order?.items.length ?? 0})',
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : null,
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
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 12),
                      const Text('Commande introuvable',
                          style:
                              TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loadOrder,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : isWide
                  ? _DesktopLayout(
                      order: _order!,
                      symbol: symbol,
                      submitting: _submitting,
                      onAddItem: _addItem,
                      onRemoveItem: _removeItem,
                      onUpdateQuantity: _updateQuantity,
                      onKitchen: _sendToKitchen,
                      onCheckout: _checkout,
                    )
                  : _MobileLayout(
                      tabCtrl: _tabCtrl,
                      order: _order!,
                      symbol: symbol,
                      submitting: _submitting,
                      onAddItem: _addItem,
                      onRemoveItem: _removeItem,
                      onUpdateQuantity: _updateQuantity,
                      onKitchen: _sendToKitchen,
                      onCheckout: _checkout,
                    ),
    );
  }
}

// ── Desktop two-panel layout ──────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final RestaurantOrderModel order;
  final String symbol;
  final bool submitting;
  final Future<void> Function(MenuItemModel, {String? notes, double? unitPrice}) onAddItem;
  final Future<void> Function(String) onRemoveItem;
  final Future<void> Function(String, double) onUpdateQuantity;
  final VoidCallback onKitchen;
  final VoidCallback onCheckout;

  const _DesktopLayout({
    required this.order,
    required this.symbol,
    required this.submitting,
    required this.onAddItem,
    required this.onRemoveItem,
    required this.onUpdateQuantity,
    required this.onKitchen,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 360,
          child: _CartColumn(
            order: order,
            symbol: symbol,
            submitting: submitting,
            onRemoveItem: onRemoveItem,
            onUpdateQuantity: onUpdateQuantity,
            onKitchen: onKitchen,
            onCheckout: onCheckout,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _ProductBrowser(onAddItem: onAddItem)),
      ],
    );
  }
}

// ── Mobile layout (tabs) ──────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final TabController tabCtrl;
  final RestaurantOrderModel order;
  final String symbol;
  final bool submitting;
  final Future<void> Function(MenuItemModel, {String? notes, double? unitPrice}) onAddItem;
  final Future<void> Function(String) onRemoveItem;
  final Future<void> Function(String, double) onUpdateQuantity;
  final VoidCallback onKitchen;
  final VoidCallback onCheckout;

  const _MobileLayout({
    required this.tabCtrl,
    required this.order,
    required this.symbol,
    required this.submitting,
    required this.onAddItem,
    required this.onRemoveItem,
    required this.onUpdateQuantity,
    required this.onKitchen,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: tabCtrl,
      children: [
        _ProductBrowser(onAddItem: onAddItem),
        _CartColumn(
          order: order,
          symbol: symbol,
          submitting: submitting,
          onRemoveItem: onRemoveItem,
          onUpdateQuantity: onUpdateQuantity,
          onKitchen: onKitchen,
          onCheckout: onCheckout,
        ),
      ],
    );
  }
}

// ── Cart column (left on desktop, tab on mobile) ──────────────────────────────

class _CartColumn extends StatelessWidget {
  final RestaurantOrderModel order;
  final String symbol;
  final bool submitting;
  final Future<void> Function(String) onRemoveItem;
  final Future<void> Function(String, double) onUpdateQuantity;
  final VoidCallback onKitchen;
  final VoidCallback onCheckout;

  const _CartColumn({
    required this.order,
    required this.symbol,
    required this.submitting,
    required this.onRemoveItem,
    required this.onUpdateQuantity,
    required this.onKitchen,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          _OrderHeader(order: order),
          if (order.sentToKitchen || order.isReady)
            _StatusBanner(status: order.status),
          const Divider(height: 1),
          Expanded(
            child: order.items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_rounded,
                            size: 48, color: AppColors.textSecondary),
                        SizedBox(height: 12),
                        Text('Aucun article',
                            style: TextStyle(color: AppColors.textSecondary)),
                        SizedBox(height: 4),
                        Text('Ajoutez des plats depuis le menu →',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: order.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = order.items[i];
                      return _OrderItemTile(
                        item: item,
                        symbol: symbol,
                        onRemove: () => onRemoveItem(item.id),
                        onDecrement: () =>
                            onUpdateQuantity(item.id, item.quantity - 1),
                        onIncrement: () =>
                            onUpdateQuantity(item.id, item.quantity + 1),
                      );
                    },
                  ),
          ),
          _BottomBar(
            order: order,
            symbol: symbol,
            submitting: submitting,
            onKitchen: onKitchen,
            onCheckout: onCheckout,
          ),
        ],
      ),
    );
  }
}

// ── Product browser (right panel) ─────────────────────────────────────────────

class _ProductBrowser extends StatefulWidget {
  final Future<void> Function(MenuItemModel, {String? notes, double? unitPrice}) onAddItem;

  const _ProductBrowser({required this.onAddItem});

  @override
  State<_ProductBrowser> createState() => _ProductBrowserState();
}

class _ProductBrowserState extends State<_ProductBrowser> {
  final _menuRepo = RestaurantRepository();
  final _prodRepo = ProductRepository();
  List<CategoryModel> _categories = [];
  List<MenuItemModel> _items = [];
  String? _selectedCategoryId;
  bool _loadingCats = true;
  bool _loadingItems = false;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCats = true);
    try {
      final cats = await _prodRepo.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loadingCats = false;
      });
      _loadItems();
    } catch (e) {
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  void _selectCategory(String? catId) {
    if (catId == _selectedCategoryId) return;
    setState(() => _selectedCategoryId = catId);
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loadingItems = true);
    try {
      final all = await _menuRepo.getMenuItems(categoryId: _selectedCategoryId);
      final q = _search.toLowerCase();
      final filtered = q.isEmpty
          ? all
          : all.where((m) => m.name.toLowerCase().contains(q)).toList();
      if (mounted) setState(() => _items = filtered);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  void _onSearchChanged(String v) {
    _search = v;
    _loadItems();
  }

  Future<void> _tapItem(MenuItemModel item) async {
    List<ModifierGroupModel> groups = [];
    try {
      final futures = <Future<List<ModifierGroupModel>>>[
        if (item.categoryId != null)
          _menuRepo.getModifierGroups(categoryId: item.categoryId),
      ];
      if (futures.isNotEmpty) {
        final results = await Future.wait(futures);
        final seen = <String>{};
        for (final list in results) {
          for (final g in list) {
            if (seen.add(g.id)) groups.add(g);
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;

    // Pas de variantes et pas de groupes → ajout direct sans dialog
    if (!item.hasVariants && groups.isEmpty) {
      await widget.onAddItem(item);
      return;
    }

    final results = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _ModifierDialog(menuItem: item, groups: groups),
    );
    if (results == null || results.isEmpty) return;
    for (final r in results) {
      await widget.onAddItem(
        item,
        notes: r['notes'] as String?,
        unitPrice: r['unit_price'] as double?,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCats) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Rechercher un plat ou une boisson…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged('');
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

        // Category filter chips
        if (_categories.isNotEmpty)
          Container(
            height: 44,
            color: AppColors.surface,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _CategoryChip(
                  label: 'Tous',
                  selected: _selectedCategoryId == null,
                  onTap: () => _selectCategory(null),
                ),
                ..._categories.map((c) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _CategoryChip(
                        label: c.name,
                        selected: _selectedCategoryId == c.id,
                        onTap: () => _selectCategory(c.id),
                      ),
                    )),
              ],
            ),
          ),

        // Menu item grid
        Expanded(
          child: _loadingItems
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48, color: AppColors.textSecondary),
                          SizedBox(height: 12),
                          Text('Aucun plat trouvé',
                              style: TextStyle(
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _MenuItemCard(
                        item: _items[i],
                        onTap: () => _tapItem(_items[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

// ── Menu item card ────────────────────────────────────────────────────────────

class _MenuItemCard extends StatelessWidget {
  final MenuItemModel item;
  final VoidCallback onTap;

  const _MenuItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.available ? onTap : null,
      child: Opacity(
        opacity: item.available ? 1.0 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 4,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(10)),
                child: SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: '${dio.options.baseUrl}${item.imageUrl}',
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _MenuItemPlaceholder(),
                          errorWidget: (_, __, ___) => _MenuItemPlaceholder(),
                        )
                      else
                        _MenuItemPlaceholder(),
                      if (item.description != null &&
                          item.description!.isNotEmpty)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.tune_rounded,
                                color: Colors.white, size: 10),
                          ),
                        ),
                      if (!item.available)
                        Container(
                          color: Colors.black38,
                          alignment: Alignment.center,
                          child: const Text('Indisponible',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      NumberFormat('#,##0.00').format(item.price),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItemPlaceholder extends StatelessWidget {
  const _MenuItemPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.restaurant_menu_rounded,
            size: 32, color: AppColors.primary),
      ),
    );
  }
}

// ── Modifier dialog ───────────────────────────────────────────────────────────
// Retourne Map{'notes': String?} ou null si annulé.

class _ModifierDialog extends StatefulWidget {
  final MenuItemModel menuItem;
  final List<ModifierGroupModel> groups;
  const _ModifierDialog({required this.menuItem, required this.groups});

  @override
  State<_ModifierDialog> createState() => _ModifierDialogState();
}

class _ModifierDialogState extends State<_ModifierDialog> {
  late final Map<String, Set<String>> _selections;
  late final Map<String, String?> _singleSelections;
  final _notesCtrl = TextEditingController();
  // multi-select variant indices
  final Set<int> _selectedVariants = {};

  @override
  void initState() {
    super.initState();
    _selections = {for (final g in widget.groups) g.id: {}};
    _singleSelections = {for (final g in widget.groups) g.id: null};
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  bool _canConfirm() {
    if (widget.menuItem.hasVariants && _selectedVariants.isEmpty) return false;
    for (final g in widget.groups) {
      if (!g.required) continue;
      if (g.multiSelect) {
        if ((_selections[g.id] ?? {}).isEmpty) return false;
      } else {
        if (_singleSelections[g.id] == null) return false;
      }
    }
    return true;
  }

  // Notes for modifier groups + free text (no variant name — handled per-item)
  String _groupNotes() {
    final parts = <String>[];
    for (final g in widget.groups) {
      if (g.multiSelect) {
        final sel = _selections[g.id] ?? {};
        final names = g.options
            .where((o) => sel.contains(o.id))
            .map((o) => o.name)
            .toList();
        if (names.isNotEmpty) parts.add('${g.name}: ${names.join(', ')}');
      } else {
        final selId = _singleSelections[g.id];
        if (selId != null) {
          final opt = g.options.where((o) => o.id == selId).firstOrNull;
          if (opt != null) parts.add('${g.name}: ${opt.name}');
        }
      }
    }
    final extra = _notesCtrl.text.trim();
    if (extra.isNotEmpty) parts.add(extra);
    return parts.join(' | ');
  }

  String _buildNotes() => _groupNotes();

  @override
  Widget build(BuildContext context) {
    final hasGroups = widget.groups.isNotEmpty;
    final variants  = widget.menuItem.variantRows;
    final hasVariants = variants.isNotEmpty;
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      title: Row(
        children: [
          const Icon(Icons.restaurant_menu_rounded,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.menuItem.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                if (widget.menuItem.description != null &&
                    widget.menuItem.description!.isNotEmpty)
                  Text(widget.menuItem.description!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.normal)),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 580),
        child: StatefulBuilder(
          builder: (_, setInner) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Variantes ──────────────────────────────────────────────
                if (hasVariants) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                    child: Row(
                      children: [
                        const Text('Choisir une variante',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(width: 4),
                        Text('*',
                            style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  ...List.generate(variants.length, (i) {
                    final row = variants[i];
                    final name = row['name']?.toString() ?? '';
                    final price = (row['price_delta'] as num?)?.toDouble() ?? 0.0;
                    final available = row['available'] as bool? ?? true;
                    final checked = _selectedVariants.contains(i);
                    final extraCols = widget.menuItem.extraColumns;
                    final extraDesc = extraCols
                        .map((c) => row[c]?.toString() ?? '')
                        .where((v) => v.isNotEmpty)
                        .join(' · ');
                    return InkWell(
                      onTap: available
                          ? () => setInner(() {
                                if (_selectedVariants.contains(i)) {
                                  _selectedVariants.remove(i);
                                } else {
                                  _selectedVariants.add(i);
                                }
                              })
                          : null,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: checked
                              ? AppColors.primary.withValues(alpha: 0.07)
                              : AppColors.surface,
                          border: Border.all(
                            color: checked
                                ? AppColors.primary
                                : AppColors.divider,
                            width: checked ? 1.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: checked,
                              onChanged: available
                                  ? (v) => setInner(() {
                                        if (v == true) {
                                          _selectedVariants.add(i);
                                        } else {
                                          _selectedVariants.remove(i);
                                        }
                                      })
                                  : null,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                      color: available
                                          ? null
                                          : AppColors.textSecondary,
                                      decoration: available
                                          ? null
                                          : TextDecoration.lineThrough,
                                    ),
                                  ),
                                  if (extraDesc.isNotEmpty)
                                    Text(
                                      extraDesc,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              price.toStringAsFixed(0),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: checked ? AppColors.primary : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
                // ── Groupes de modificateurs ───────────────────────────────
                ...widget.groups.map((g) => _GroupSection(
                      group: g,
                      singleValue: _singleSelections[g.id],
                      multiValues: _selections[g.id] ?? {},
                      onSingleChanged: (optId) =>
                          setInner(() => _singleSelections[g.id] = optId),
                      onMultiChanged: (optId, checked) => setInner(() {
                        if (checked) {
                          _selections[g.id]!.add(optId);
                        } else {
                          _selections[g.id]!.remove(optId);
                        }
                      }),
                    )),
                // ── Notes / Instructions (masquées si variantes) ───────────
                if (!hasVariants)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasGroups) const Divider(height: 1),
                        if (hasGroups) const SizedBox(height: 12),
                        Text(
                          hasGroups ? 'Remarques supplémentaires' : 'Instructions',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _notesCtrl,
                          maxLines: 2,
                          autofocus: !hasGroups,
                          onChanged: (_) => setInner(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Ex: sans sel, bien cuit…',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (hasVariants) const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _canConfirm()
              ? () {
                  final groupExtra = _groupNotes();
                  final rows = widget.menuItem.variantRows;
                  final results = <Map<String, dynamic>>[];
                  if (widget.menuItem.hasVariants) {
                    for (final i
                        in _selectedVariants.toList()..sort()) {
                      if (i >= rows.length) continue;
                      final row = rows[i];
                      final variantName =
                          row['name']?.toString() ?? '';
                      final price =
                          (row['price_delta'] as num?)?.toDouble();
                      final noteParts = [
                        if (variantName.isNotEmpty) variantName,
                        if (groupExtra.isNotEmpty) groupExtra,
                      ];
                      results.add({
                        'notes': noteParts.isEmpty
                            ? null
                            : noteParts.join(' | '),
                        if (price != null && price > 0)
                          'unit_price': price,
                      });
                    }
                  } else {
                    final notes = _buildNotes();
                    results.add(
                        {'notes': notes.isEmpty ? null : notes});
                  }
                  Navigator.pop(context, results);
                }
              : null,
          icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
          label: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _GroupSection extends StatelessWidget {
  final ModifierGroupModel group;
  final String? singleValue;
  final Set<String> multiValues;
  final ValueChanged<String?> onSingleChanged;
  final void Function(String optId, bool checked) onMultiChanged;

  const _GroupSection({
    required this.group,
    required this.singleValue,
    required this.multiValues,
    required this.onSingleChanged,
    required this.onMultiChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header
        Container(
          color: AppColors.primary.withValues(alpha: 0.06),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(group.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary)),
              ),
              if (group.required)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Requis',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.error,
                          fontWeight: FontWeight.w600)),
                ),
              if (!group.required)
                const Text('Optionnel',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
        // Options
        if (group.multiSelect)
          ...group.options.map((opt) {
            final label = opt.extraPrice > 0
                ? '${opt.name}  (+${opt.extraPrice.toStringAsFixed(0)})'
                : opt.name;
            return CheckboxListTile(
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12),
              title:
                  Text(label, style: const TextStyle(fontSize: 13)),
              value: multiValues.contains(opt.id),
              activeColor: AppColors.primary,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => onMultiChanged(opt.id, v == true),
            );
          })
        else
          RadioGroup<String>(
            groupValue: singleValue,
            onChanged: onSingleChanged,
            child: Column(
              children: group.options.map((opt) {
                final label = opt.extraPrice > 0
                    ? '${opt.name}  (+${opt.extraPrice.toStringAsFixed(0)})'
                    : opt.name;
                return RadioListTile<String>(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  title: Text(label,
                      style: const TextStyle(fontSize: 13)),
                  value: opt.id,
                  activeColor: AppColors.primary,
                );
              }).toList(),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

// ── Order header ──────────────────────────────────────────────────────────────

class _OrderHeader extends StatelessWidget {
  final RestaurantOrderModel order;
  const _OrderHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    final tableLabel =
        order.hasTable ? (order.tableName ?? 'Table') : 'Comptoir / Bar';

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _InfoChip(
            icon: order.hasTable
                ? Icons.table_restaurant_rounded
                : Icons.countertops_rounded,
            label: tableLabel,
          ),
          _InfoChip(
            icon: Icons.people_outline_rounded,
            label:
                '${order.covers} couvert${order.covers > 1 ? 's' : ''}',
          ),
          if (order.waiterName != null)
            _InfoChip(
              icon: Icons.person_outline_rounded,
              label: order.waiterName!,
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Status banner ──────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Order item tile ────────────────────────────────────────────────────────────

class _OrderItemTile extends StatelessWidget {
  final RestaurantOrderItemModel item;
  final String symbol;
  final VoidCallback onRemove;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _OrderItemTile({
    required this.item,
    required this.symbol,
    required this.onRemove,
    required this.onDecrement,
    required this.onIncrement,
  });

  Color get _statusColor {
    if (item.status == 'ready') return AppColors.success;
    if (item.status == 'preparing') return AppColors.warning;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final qtyInt = item.quantity == item.quantity.roundToDouble();
    final qtyLabel = qtyInt
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Quantity stepper
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onDecrement,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: item.quantity <= 1
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    item.quantity <= 1
                        ? Icons.delete_outline_rounded
                        : Icons.remove_rounded,
                    size: 14,
                    color: item.quantity <= 1
                        ? AppColors.error
                        : AppColors.primary,
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  qtyLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 13),
                ),
              ),
              InkWell(
                onTap: onIncrement,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 14, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12)),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Text(item.notes!,
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic)),
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
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
                      style: TextStyle(fontSize: 10, color: _statusColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Price + delete
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$symbol${NumberFormat('#,##0.00').format(item.subtotal)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12),
              ),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      color: AppColors.error, size: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
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
                      fontWeight: FontWeight.w600, fontSize: 15)),
              Text(
                '$symbol${NumberFormat('#,##0.00').format(order.total)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!order.sentToKitchen && !order.isReady)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: submitting || order.items.isEmpty
                        ? null
                        : onKitchen,
                    icon: const Icon(Icons.restaurant_rounded, size: 16),
                    label: const Text('Cuisine',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
              if (!order.sentToKitchen && !order.isReady)
                const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: submitting || order.items.isEmpty
                      ? null
                      : onCheckout,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success),
                  icon: submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.point_of_sale_rounded,
                          size: 16),
                  label: const Text('Encaisser',
                      style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Checkout dialog ───────────────────────────────────────────────────────────

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
                      style: const TextStyle(
                          color: AppColors.textSecondary)),
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
                  prefixIcon: const Icon(
                      Icons.volunteer_activism_rounded,
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
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _paidCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Montant reçu',
                    prefixText: widget.symbol),
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
