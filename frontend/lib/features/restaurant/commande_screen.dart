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

  Future<void> _addItem(ProductModel product, {String? notes}) async {
    if (_order == null) return;
    setState(() => _submitting = true);
    try {
      _order = await _repo.addItem(_order!.id, productId: product.id, notes: notes);
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
  final Future<void> Function(ProductModel, {String? notes}) onAddItem;
  final Future<void> Function(String) onRemoveItem;
  final VoidCallback onKitchen;
  final VoidCallback onCheckout;

  const _DesktopLayout({
    required this.order,
    required this.symbol,
    required this.submitting,
    required this.onAddItem,
    required this.onRemoveItem,
    required this.onKitchen,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: order / cart panel
        SizedBox(
          width: 360,
          child: _CartColumn(
            order: order,
            symbol: symbol,
            submitting: submitting,
            onRemoveItem: onRemoveItem,
            onKitchen: onKitchen,
            onCheckout: onCheckout,
          ),
        ),
        const VerticalDivider(width: 1),
        // Right: product browser
        Expanded(
          child: _ProductBrowser(onAddItem: onAddItem),
        ),
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
  final Future<void> Function(ProductModel, {String? notes}) onAddItem;
  final Future<void> Function(String) onRemoveItem;
  final VoidCallback onKitchen;
  final VoidCallback onCheckout;

  const _MobileLayout({
    required this.tabCtrl,
    required this.order,
    required this.symbol,
    required this.submitting,
    required this.onAddItem,
    required this.onRemoveItem,
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
  final VoidCallback onKitchen;
  final VoidCallback onCheckout;

  const _CartColumn({
    required this.order,
    required this.symbol,
    required this.submitting,
    required this.onRemoveItem,
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
                        Text(
                          'Aucun article',
                          style:
                              TextStyle(color: AppColors.textSecondary),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Ajoutez des plats depuis le menu →',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: order.items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) => _OrderItemTile(
                      item: order.items[i],
                      symbol: symbol,
                      onRemove: () => onRemoveItem(order.items[i].id),
                    ),
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
  final Future<void> Function(ProductModel, {String? notes}) onAddItem;

  const _ProductBrowser({required this.onAddItem});

  @override
  State<_ProductBrowser> createState() => _ProductBrowserState();
}

class _ProductBrowserState extends State<_ProductBrowser> {
  final _repo = ProductRepository();
  List<CategoryModel> _categories = [];
  List<ProductModel> _products = [];
  String? _selectedCategoryId; // null = "Tous"
  bool _loadingCats = true;
  bool _loadingProds = false;
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
      final cats = await _repo.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loadingCats = false;
      });
      _loadProducts();
    } catch (e) {
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  void _selectCategory(String? catId) {
    if (catId == _selectedCategoryId) return;
    _selectedCategoryId = catId;
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProds = true);
    try {
      final result = await _repo.getProducts(
        categoryId: _selectedCategoryId,
        search: _search.isEmpty ? null : _search,
        limit: 60,
      );
      if (mounted) setState(() => _products = result.data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingProds = false);
    }
  }

  void _onSearchChanged(String v) {
    _search = v;
    _loadProducts();
  }

  Future<void> _tapProduct(ProductModel product) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => _ProductNotesDialog(product: product),
    );
    if (notes == null) return; // cancelled (dialog dismissed)
    await widget.onAddItem(product,
        notes: notes.isEmpty ? null : notes);
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

        // Product grid
        Expanded(
          child: _loadingProds
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48, color: AppColors.textSecondary),
                          SizedBox(height: 12),
                          Text('Aucun produit trouvé',
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
                      itemCount: _products.length,
                      itemBuilder: (_, i) => _ProductCard(
                        product: _products[i],
                        onTap: () => _tapProduct(_products[i]),
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

// ── Product card ──────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                    if (product.imageUrl != null &&
                        product.imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl:
                            '${dio.options.baseUrl}${product.imageUrl}',
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            _ProductPlaceholder(product: product),
                        errorWidget: (_, __, ___) =>
                            _ProductPlaceholder(product: product),
                      )
                    else
                      _ProductPlaceholder(product: product),
                    if (product.description != null &&
                        product.description!.isNotEmpty)
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
                    product.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    NumberFormat('#,##0.00').format(product.salePrice),
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
    );
  }
}

class _ProductPlaceholder extends StatelessWidget {
  final ProductModel product;
  const _ProductPlaceholder({required this.product});

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

// ── Product notes / customization dialog ──────────────────────────────────────

class _ProductNotesDialog extends StatefulWidget {
  final ProductModel product;
  const _ProductNotesDialog({required this.product});

  @override
  State<_ProductNotesDialog> createState() => _ProductNotesDialogState();
}

class _ProductNotesDialogState extends State<_ProductNotesDialog> {
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.restaurant_menu_rounded,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.product.name,
                style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.product.description != null &&
              widget.product.description!.isNotEmpty) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.product.description!,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Instructions / personnalisation',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Ex: sans oignons, extra fromage…',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _notesCtrl.text),
          icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
          label: const Text('Ajouter'),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
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
                  fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Text(item.notes!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
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
                      style:
                          TextStyle(fontSize: 10, color: _statusColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '$symbol${NumberFormat('#,##0.00').format(item.subtotal)}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                color: AppColors.error, size: 18),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
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
