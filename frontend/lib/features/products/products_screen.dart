import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/data/repositories/product_repository.dart';
import 'package:pos_connect/providers/permission_provider.dart';
import 'package:pos_connect/providers/product_provider.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/services/offline_cache_service.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';
import 'package:pos_connect/data/repositories/warehouse_repository.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

final _fmt =
    NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);

String _imgUrl(String path) => '${dio.options.baseUrl}$path';

/// /api/products/ plafonne per_page à 100 — on pagine pour tout récupérer.
Future<List<ProductModel>> _fetchAllProductsForPicker() async {
  const perPage = 100;
  final repo = ProductRepository();
  final first = await repo.getProducts(page: 1, limit: perPage);
  final all = [...first.data];
  for (var p = 2; p <= first.meta.pages; p++) {
    final res = await repo.getProducts(page: p, limit: perPage);
    all.addAll(res.data);
  }
  return all;
}

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bt = ref.watch(settingsProvider).businessType;
    final isRestaurant = bt == 'restaurant' || bt == 'hotel';

    if (isRestaurant) {
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const _ProductsToolbar(),
            const Divider(height: 1),
            Container(
              color: AppColors.surface,
              child: const TabBar(
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: [
                  Tab(text: 'Produits / Stock'),
                  Tab(text: 'Menu / Plats'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ProductsBody(),
                  _MenuPanel(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        const _ProductsToolbar(),
        const Divider(height: 1),
        const Expanded(child: _ProductsBody()),
      ],
    );
  }
}

// ── Products body (extracted for reuse in tabs) ───────────────────────────────

class _ProductsBody extends ConsumerWidget {
  const _ProductsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      data: (products) {
        final isWide = MediaQuery.sizeOf(context).width >= 700;
        Future<void> onRefresh() async {
          await OfflineCacheService.instance.syncAll();
          ref.invalidate(productsProvider);
        }

        if (products.data.isEmpty) {
          if (!isWide) {
            return RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: const Center(
                      child: Text('Aucun produit trouvé',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              ),
            );
          }
          return const Center(
              child: Text('Aucun produit trouvé',
                  style: TextStyle(color: AppColors.textSecondary)));
        }
        if (isWide) return _ProductTable(products: products.data);
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: products.data.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) =>
                _ProductCard(product: products.data[i]),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Erreur: $e',
              style: const TextStyle(color: AppColors.error))),
    );
  }
}

// ── Variant row state ─────────────────────────────────────────────────────────

class _VRow {
  bool available;
  final TextEditingController name;
  final TextEditingController price;
  final List<TextEditingController> extra;

  _VRow({
    this.available = true,
    String nameText = '',
    String priceText = '0',
    List<String> extraTexts = const [],
  })  : name = TextEditingController(text: nameText),
        price = TextEditingController(text: priceText),
        extra = extraTexts.map((t) => TextEditingController(text: t)).toList();

  void dispose() {
    name.dispose();
    price.dispose();
    for (final c in extra) c.dispose();
  }

  Map<String, dynamic> toMap(List<String> colNames) => {
        'name': name.text.trim(),
        'price_delta': double.tryParse(price.text) ?? 0.0,
        'available': available,
        for (int i = 0; i < colNames.length && i < extra.length; i++)
          colNames[i]: extra[i].text.trim(),
      };
}

// ── Menu panel (restaurant only) ──────────────────────────────────────────────

class _MenuPanel extends ConsumerStatefulWidget {
  const _MenuPanel();
  @override
  ConsumerState<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends ConsumerState<_MenuPanel> {
  final _repo = RestaurantRepository();
  final _prodRepo = ProductRepository();
  List<MenuItemModel> _items = [];
  List<CategoryModel> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _repo.getMenuItems(),
        _prodRepo.getCategories(),
      ]);
      if (mounted) {
        setState(() {
          _items = results[0] as List<MenuItemModel>;
          _categories = results[1] as List<CategoryModel>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final canCreate = ref.watch(hasPermissionProvider(Perm.tablesCreate));
    final canEdit   = ref.watch(hasPermissionProvider(Perm.tablesUpdate));
    final canDelete = ref.watch(hasPermissionProvider(Perm.tablesDelete));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_items.length} plat${_items.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
              if (canCreate)
                ElevatedButton.icon(
                  onPressed: () => _showForm(),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Nouveau plat'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!,
                style: const TextStyle(color: AppColors.error)),
          ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_items.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.restaurant_menu_rounded,
                      size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text('Aucun plat dans le menu',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
          )
        else if (isWide)
          Expanded(child: _MenuTable(
            items: _items,
            canEdit: canEdit,
            canDelete: canDelete,
            onEdit: (m) => _showForm(m),
            onDelete: (m) => _confirmDelete(context, m),
            onToggle: _toggleAvailable,
          ))
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _MenuItemTile(
                item: _items[i],
                canEdit: canEdit,
                canDelete: canDelete,
                onEdit: () => _showForm(_items[i]),
                onDelete: () => _confirmDelete(context, _items[i]),
                onToggle: () => _toggleAvailable(_items[i]),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _toggleAvailable(MenuItemModel m) async {
    try {
      await _repo.updateMenuItem(m.id, available: !m.available);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : ${extractAnyError(e)}'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _showForm([MenuItemModel? m]) async {
    // Recharge catégories + dépôts
    List<WarehouseModel> warehouses = [];
    try {
      final results = await Future.wait([
        ProductRepository().getCategories(),
        WarehouseRepository().listWarehouses(),
      ]);
      if (mounted) setState(() => _categories = results[0] as List<CategoryModel>);
      warehouses = results[1] as List<WarehouseModel>;
    } catch (_) {}
    if (!mounted) return;
    final nameCtrl  = TextEditingController(text: m?.name ?? '');
    final descCtrl  = TextEditingController(text: m?.description ?? '');
    final priceCtrl = TextEditingController(
        text: m != null ? m.price.toStringAsFixed(2) : '');
    String? selectedCatId = m?.categoryId;
    String? selectedWarehouseId = m?.warehouseId;
    bool available = m?.available ?? true;
    bool sendToKitchen = m?.sendToKitchen ?? true;

    // Variants state
    final existingCols = m?.extraColumns ?? [];
    final existingRows = m?.variantRows ?? [];
    bool hasVariants = existingRows.isNotEmpty;
    final colCtrls = existingCols
        .map((c) => TextEditingController(text: c))
        .toList();
    final vRows = existingRows
        .map((r) => _VRow(
              available: r['available'] as bool? ?? true,
              nameText:  r['name']?.toString() ?? '',
              priceText: (r['price_delta'] ?? 0).toString(),
              extraTexts: existingCols
                  .map((c) => r[c]?.toString() ?? '')
                  .toList(),
            ))
        .toList();

    final messenger = ScaffoldMessenger.of(context);
    const kNom   = 148.0;
    const kPrix  = 82.0;
    const kDispo = 56.0;
    const kExtra = 118.0;
    const kDel   = 36.0;
    const cellPad = EdgeInsets.symmetric(horizontal: 5, vertical: 4);
    const hdrStyle = TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    const tfDeco = InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          List<String> colNames() => List.generate(colCtrls.length, (i) {
                final t = colCtrls[i].text.trim();
                return t.isEmpty ? 'col_${i + 1}' : t;
              });

          Widget hdr(String t, double w) => Padding(
                padding: cellPad,
                child: SizedBox(
                    width: w,
                    child: Text(t, style: hdrStyle, overflow: TextOverflow.ellipsis)),
              );

          Widget dataTf(double w, TextEditingController c,
                  {String? hint, TextInputType? kt}) =>
              Padding(
                padding: cellPad,
                child: SizedBox(
                  width: w,
                  child: TextField(
                    controller: c,
                    keyboardType: kt,
                    decoration: hint != null
                        ? tfDeco.copyWith(hintText: hint)
                        : tfDeco,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              );

          return AlertDialog(
            title: Text(m == null ? 'Nouveau plat' : 'Modifier le plat'),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            content: SizedBox(
              width: 700,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Infos de base ─────────────────────────────────────
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Nom du plat *'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Description (optionnel)'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedCatId,
                      decoration: const InputDecoration(
                          labelText: 'Catégorie (optionnel)'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— Aucune —')),
                        ..._categories.map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => setInner(() => selectedCatId = v),
                    ),
                    if (warehouses.length > 1) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedWarehouseId,
                        decoration: const InputDecoration(
                            labelText: 'Dépôt (optionnel)',
                            prefixIcon: Icon(Icons.warehouse_outlined, size: 18)),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('— Tous les dépôts —')),
                          ...warehouses.map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Row(
                                children: [
                                  Text(w.name),
                                  if (w.isDefault) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('défaut',
                                          style: TextStyle(fontSize: 10, color: AppColors.primary)),
                                    ),
                                  ],
                                ],
                              ))),
                        ],
                        onChanged: (v) => setInner(() => selectedWarehouseId = v),
                      ),
                    ],
                    const Divider(height: 24),
                    // ── Variantes ─────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text('Variantes de prix',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text('Ex: Petit / Normal / Grand avec prix différents',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Switch(
                          value: hasVariants,
                          onChanged: (v) => setInner(() {
                            hasVariants = v;
                            if (v && vRows.isEmpty) {
                              vRows.add(_VRow(
                                  extraTexts:
                                      List.filled(colCtrls.length, '')));
                            }
                          }),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    if (hasVariants) ...[
                      const SizedBox(height: 6),
                      // ── Bandeau orange info prix ──────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.10),
                          border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.45)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.info_outline_rounded,
                                size: 14, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Quand une variante est sélectionnée, c\'est son prix qui sera utilisé — le prix de base est ignoré.',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          border: Border.all(color: AppColors.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Header ──────────────────────────────────
                              Row(
                                children: [
                                  hdr('Nom *', kNom),
                                  ...List.generate(colCtrls.length, (ci) => Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding: cellPad,
                                        child: SizedBox(
                                          width: kExtra,
                                          child: TextField(
                                            controller: colCtrls[ci],
                                            decoration: tfDeco.copyWith(
                                                hintText: 'Colonne ${ci + 1}'),
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: kDel,
                                        child: IconButton(
                                          icon: const Icon(
                                              Icons.close_rounded,
                                              size: 13,
                                              color: AppColors.error),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: kDel, minHeight: kDel),
                                          tooltip: 'Supprimer la colonne',
                                          onPressed: () => setInner(() {
                                            colCtrls[ci].dispose();
                                            colCtrls.removeAt(ci);
                                            for (final r in vRows) {
                                              if (ci < r.extra.length) {
                                                r.extra[ci].dispose();
                                                r.extra.removeAt(ci);
                                              }
                                            }
                                          }),
                                        ),
                                      ),
                                    ],
                                  )),
                                  hdr('Δ Prix (HTG)', kPrix),
                                  hdr('Dispo', kDispo),
                                  // Placeholder aligning with row-delete btn
                                  SizedBox(width: kDel),
                                ],
                              ),
                              const Divider(height: 8),
                              // ── Rows ────────────────────────────────────
                              ...List.generate(vRows.length, (ri) {
                                final row = vRows[ri];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      dataTf(kNom, row.name, hint: 'Ex: Normal'),
                                      ...List.generate(
                                          colCtrls.length,
                                          (ci) => Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              dataTf(
                                                kExtra,
                                                ci < row.extra.length
                                                    ? row.extra[ci]
                                                    : TextEditingController(),
                                              ),
                                              SizedBox(width: kDel),
                                            ],
                                          )),
                                      dataTf(kPrix, row.price,
                                          hint: '0',
                                          kt: const TextInputType
                                              .numberWithOptions(
                                              signed: true, decimal: true)),
                                      SizedBox(
                                        width: kDispo,
                                        child: Switch(
                                          value: row.available,
                                          onChanged: (v) => setInner(
                                              () => row.available = v),
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      // Row delete
                                      SizedBox(
                                        width: kDel,
                                        child: IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 16,
                                              color: AppColors.error),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: kDel, minHeight: kDel),
                                          onPressed: () => setInner(() {
                                            row.dispose();
                                            vRows.removeAt(ri);
                                          }),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Buttons: add row + add column
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => setInner(() {
                              vRows.add(_VRow(
                                  extraTexts:
                                      List.filled(colCtrls.length, '')));
                            }),
                            icon: const Icon(Icons.add_rounded, size: 14),
                            label: const Text('+ Ligne',
                                style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: const Size(0, 28)),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => setInner(() {
                              colCtrls.add(TextEditingController());
                              for (final r in vRows) {
                                r.extra.add(TextEditingController());
                              }
                            }),
                            icon: const Icon(Icons.view_column_rounded,
                                size: 14),
                            label: const Text('+ Colonne',
                                style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: const Size(0, 28)),
                          ),
                        ],
                      ),
                    ],
                    // ── Prix + Dispo ──────────────────────────────────────
                    const Divider(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Prix de base (HTG) *'),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Plat disponible',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                            Switch(
                              value: available,
                              onChanged: (v) => setInner(() => available = v),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                      ],
                    ),
                    // ── Bandeau violet cuisine ────────────────────────────
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => setInner(
                          () => sendToKitchen = !sendToKitchen),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple
                              .withValues(alpha: sendToKitchen ? 0.10 : 0.04),
                          border: Border.all(
                            color: Colors.deepPurple.withValues(
                                alpha: sendToKitchen ? 0.45 : 0.20),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: sendToKitchen,
                              onChanged: (v) => setInner(
                                  () => sendToKitchen = v ?? true),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              activeColor: Colors.deepPurple,
                              side: BorderSide(
                                color: Colors.deepPurple
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Envoyer en cuisine',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.deepPurple)),
                                  Text(
                                    sendToKitchen
                                        ? 'Ce plat sera préparé en cuisine lors d\'une commande'
                                        : 'Ce plat ne passe pas en cuisine (boisson, emballage…)',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.deepPurple
                                            .withValues(alpha: 0.7)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
                  child: const Text('Annuler')),
              ElevatedButton(
                onPressed: () async {
                  final name  = nameCtrl.text.trim();
                  final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                  if (name.isEmpty) return;
                  Navigator.pop(ctx);

                  final names = colNames();
                  Map<String, dynamic>? variantsPayload;
                  if (hasVariants) {
                    final rows = vRows
                        .map((r) => r.toMap(names))
                        .where((r) =>
                            (r['name'] as String).isNotEmpty)
                        .toList();
                    variantsPayload = {
                      'extra_columns': names,
                      'rows': rows,
                    };
                  } else {
                    variantsPayload = {};
                  }

                  try {
                    if (m == null) {
                      await _repo.createMenuItem(
                        name: name,
                        description: descCtrl.text.trim().isEmpty
                            ? null
                            : descCtrl.text.trim(),
                        price: price,
                        categoryId: selectedCatId,
                        available: available,
                        sendToKitchen: sendToKitchen,
                        variants:
                            variantsPayload.isEmpty ? null : variantsPayload,
                        warehouseId: selectedWarehouseId,
                      );
                    } else {
                      await _repo.updateMenuItem(m.id,
                        name: name,
                        description: descCtrl.text.trim().isEmpty
                            ? null
                            : descCtrl.text.trim(),
                        price: price,
                        categoryId: selectedCatId,
                        available: available,
                        sendToKitchen: sendToKitchen,
                        variants: variantsPayload,
                        warehouseId: selectedWarehouseId,
                      );
                    }
                    _load();
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(SnackBar(
                        content: Text('Erreur : ${extractAnyError(e)}'),
                        backgroundColor: AppColors.error,
                      ));
                    }
                  }
                },
                child: Text(m == null ? 'Créer' : 'Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, MenuItemModel m) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le plat ?'),
        content: Text('Supprimer "${m.name}" du menu ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _repo.deleteMenuItem(m.id);
                _load();
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('Erreur : ${extractAnyError(e)}'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _MenuTable extends StatelessWidget {
  final List<MenuItemModel> items;
  final bool canEdit;
  final bool canDelete;
  final void Function(MenuItemModel) onEdit;
  final void Function(MenuItemModel) onDelete;
  final void Function(MenuItemModel) onToggle;
  const _MenuTable({required this.items, this.canEdit = true, this.canDelete = true, required this.onEdit, required this.onDelete, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(1.5),
          3: FixedColumnWidth(80),
          4: FixedColumnWidth(96),
        },
        children: [
          TableRow(
            decoration:
                BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06)),
            children: const [
              _TH('Nom'),
              _TH('Catégorie'),
              _TH('Prix'),
              _TH('Dispo'),
              _TH(''),
            ],
          ),
          ...items.map((m) => TableRow(
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: AppColors.divider))),
                children: [
                  _TD(m.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  _TD(m.categoryName ?? '—'),
                  _TD(fmt.format(m.price),
                      style: const TextStyle(color: AppColors.primary)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Switch(
                      value: m.available,
                      onChanged: (_) => onToggle(m),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: 16, color: AppColors.textSecondary),
                          onPressed: () => onEdit(m),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      if (canDelete)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 16, color: AppColors.error),
                          onPressed: () => onDelete(m),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                    ],
                  ),
                ],
              )),
        ],
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  final MenuItemModel item;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  const _MenuItemTile({required this.item, this.canEdit = true, this.canDelete = true, required this.onEdit, required this.onDelete, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor:
              (item.available ? AppColors.primary : AppColors.textSecondary)
                  .withValues(alpha: 0.12),
          child: Icon(Icons.restaurant_menu_rounded,
              size: 18,
              color: item.available
                  ? AppColors.primary
                  : AppColors.textSecondary),
        ),
        title: Text(item.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(
            '${item.categoryName ?? '—'} · ${NumberFormat('#,##0.00').format(item.price)} HTG',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: item.available, onChanged: (_) => onToggle(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 16, color: AppColors.textSecondary),
                onPressed: onEdit,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            if (canDelete)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 16, color: AppColors.error),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.textSecondary)),
      );
}

class _TD extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _TD(this.text, {this.style});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text,
            style: style ?? const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis),
      );
}

// ─── Toolbar ─────────────────────────────────────────────────────────────────

class _ProductsToolbar extends ConsumerWidget {
  const _ProductsToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = context.isMobile;
    final canCreate = ref.watch(hasPermissionProvider(Perm.productsCreate));
    final canManageCat = ref.watch(hasPermissionProvider(Perm.productsUpdate));
    final bt2 = ref.watch(settingsProvider).businessType;
    final isRestaurant = bt2 == 'restaurant' || bt2 == 'hotel';

    final searchField = TextField(
      decoration: const InputDecoration(
        hintText: 'Rechercher un produit...',
        prefixIcon: Icon(Icons.search_rounded, size: 20),
        isDense: true,
      ),
      onChanged: (v) => ref.read(productSearchProvider.notifier).state = v,
    );

    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.all(context.hPad),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                if (canCreate || canManageCat) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (canManageCat) ...[
                        OutlinedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => const _CategoryManagerDialog(),
                          ),
                          icon: const Icon(Icons.category_rounded, size: 18),
                          label: const Text('Catégories'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (canManageCat && isRestaurant) ...[
                        OutlinedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => const _ModifierManagerDialog(),
                          ),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('Modificateurs'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (canCreate)
                        ElevatedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => const _ProductFormDialog(),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Nouveau'),
                        ),
                    ],
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Expanded(child: searchField),
                if (canManageCat) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _CategoryManagerDialog(),
                    ),
                    icon: const Icon(Icons.category_rounded, size: 18),
                    label: const Text('Catégories'),
                  ),
                ],
                if (canManageCat && isRestaurant) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _ModifierManagerDialog(),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Modificateurs'),
                  ),
                ],
                if (canCreate) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _ProductFormDialog(),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Nouveau produit'),
                  ),
                ],
              ],
            ),
    );
  }
}

// ─── Thumbnail ────────────────────────────────────────────────────────────────

class _ProductThumb extends StatelessWidget {
  final String? imageUrl;
  final double size;
  const _ProductThumb({this.imageUrl, this.size = 44});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: _imgUrl(imageUrl!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.inventory_2_rounded,
            color: AppColors.primary, size: size * 0.5),
      );
}

// ─── Table ────────────────────────────────────────────────────────────────────

class _ProductTable extends ConsumerWidget {
  final List<ProductModel> products;
  const _ProductTable({required this.products});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(hasPermissionProvider(Perm.productsUpdate));
    final canAdjustStock = ref.watch(hasPermissionProvider(Perm.stockAdjust));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, constraints) {
        return Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // ConstrainedBox étire le tableau sur toute la largeur disponible —
          // DataTable se limite sinon à la largeur intrinsèque de ses colonnes,
          // laissant un grand vide à droite sur les fenêtres larges.
          child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth - 32),
          child: DataTable(
            // columnSpacing par défaut (56) pousse la colonne d'actions
            // (verrou + crayon) hors de la zone visible sur une fenêtre de
            // largeur standard, avec 9 colonnes — resserré ici pour que le
            // bouton d'édition reste visible sans scroll horizontal.
            columnSpacing: 20,
            horizontalMargin: 16,
            headingRowColor: WidgetStateProperty.all(AppColors.background),
            columns: [
              const DataColumn(label: Text('')),
              const DataColumn(label: Text('Produit')),
              const DataColumn(label: Text('Catégorie')),
              const DataColumn(label: Text('Prix achat'), numeric: true),
              const DataColumn(label: Text('Prix vente'), numeric: true),
              DataColumn(
                numeric: true,
                label: Tooltip(
                  message: 'Marge = (Prix vente − Prix achat) / Prix achat × 100\n'
                      'Indique le bénéfice réalisé par rapport au coût d\'achat.',
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Marge'),
                      SizedBox(width: 4),
                      Icon(Icons.info_outline_rounded,
                          size: 13, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const DataColumn(label: Text('Stock')),
              const DataColumn(label: Text('Seuil alerte'), numeric: true),
              if (canEdit || canAdjustStock) const DataColumn(label: Text(''), numeric: true),
            ],
            rows: products.map((p) {
              return DataRow(cells: [
                DataCell(_ProductThumb(imageUrl: p.imageUrl, size: 36)),
                DataCell(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    if (p.barcode != null)
                      Text(p.barcode!,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                  ],
                )),
                DataCell(Text(p.category?.name ?? '—',
                    style: const TextStyle(fontSize: 13))),
                DataCell(Text(_fmt.format(p.purchasePrice),
                    style: const TextStyle(fontSize: 13))),
                DataCell(Text(_fmt.format(p.salePrice),
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13))),
                DataCell(_MarginChip(
                    purchasePrice: p.purchasePrice, salePrice: p.salePrice)),
                DataCell(_StockChip(product: p)),
                DataCell(Text('${p.alertStock}',
                    style: const TextStyle(fontSize: 13))),
                if (canEdit || canAdjustStock)
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canAdjustStock)
                        IconButton(
                          icon: const Icon(Icons.add_box_outlined,
                              size: 18, color: AppColors.accent),
                          tooltip: 'Ajuster stock',
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => _AdjustStockDialog(product: p),
                          ),
                        ),
                      if (canEdit)
                        IconButton(
                          icon: Icon(
                              p.isLocked
                                  ? Icons.lock_outline
                                  : Icons.lock_open_outlined,
                              size: 18,
                              color: p.isLocked
                                  ? AppColors.error
                                  : AppColors.textSecondary),
                          tooltip: p.isLocked
                              ? 'Verrouillé — masqué de la caisse. Cliquer pour déverrouiller'
                              : 'Verrouiller — masquer ce produit de la caisse',
                          onPressed: () => _toggleLock(context, ref, p),
                        ),
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: 18, color: AppColors.textSecondary),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => _ProductFormDialog(product: p),
                          ),
                        ),
                    ],
                  )),
              ]);
            }).toList(),
          ),
          ),
        ),
        );
      }),
    );
  }

  Future<void> _toggleLock(
      BuildContext context, WidgetRef ref, ProductModel p) async {
    try {
      await ProductRepository().updateProduct(p.id, {
        'name': p.name,
        'barcode': p.barcode,
        'description': p.description,
        'category_id': p.category?.id,
        'sale_price': p.salePrice,
        'purchase_price': p.purchasePrice,
        'alert_stock': p.alertStock,
        'warehouse_id': p.warehouseId,
        'is_locked': !p.isLocked,
      });
      ref.invalidate(productsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${extractAnyError(e)}'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }
}

class _StockChip extends StatelessWidget {
  final ProductModel product;
  const _StockChip({required this.product});

  @override
  Widget build(BuildContext context) {
    if (product.stock == null) {
      return const Text('—', style: TextStyle(fontSize: 13));
    }
    final color = product.isLowStock ? AppColors.error : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text('${product.stock}',
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _MarginChip extends StatelessWidget {
  final double purchasePrice;
  final double salePrice;
  const _MarginChip({required this.purchasePrice, required this.salePrice});

  @override
  Widget build(BuildContext context) {
    if (purchasePrice <= 0) {
      return const Text('—', style: TextStyle(fontSize: 13, color: AppColors.textSecondary));
    }
    final margin = (salePrice - purchasePrice) / purchasePrice * 100;
    final color = margin >= 30
        ? AppColors.accent
        : margin >= 10
            ? Colors.orange
            : AppColors.error;
    return Text(
      '${margin.toStringAsFixed(1)}%',
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
    );
  }
}

// ─── Card (mobile) ────────────────────────────────────────────────────────────

class _ProductCard extends ConsumerWidget {
  final ProductModel product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(hasPermissionProvider(Perm.productsUpdate));
    final canAdjust = ref.watch(hasPermissionProvider(Perm.stockAdjust));

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _ProductThumb(imageUrl: product.imageUrl),
        title: Text(product.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(product.category?.name ?? 'Sans catégorie',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_fmt.format(product.salePrice),
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            if (product.stock != null)
              canAdjust
                  ? GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => _AdjustStockDialog(product: product),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_rounded,
                              size: 10,
                              color: product.isLowStock
                                  ? AppColors.error
                                  : AppColors.textSecondary),
                          const SizedBox(width: 3),
                          Text('Stock: ${product.stock}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: product.isLowStock
                                      ? AppColors.error
                                      : AppColors.textSecondary)),
                        ],
                      ),
                    )
                  : Text('Stock: ${product.stock}',
                      style: TextStyle(
                          fontSize: 12,
                          color: product.isLowStock
                              ? AppColors.error
                              : AppColors.textSecondary)),
          ],
        ),
        onTap: canEdit
            ? () => showDialog(
                  context: context,
                  builder: (_) => _ProductFormDialog(product: product),
                )
            : null,
      ),
    );
  }
}

// ─── Form Dialog ──────────────────────────────────────────────────────────────

class _ProductFormDialog extends ConsumerStatefulWidget {
  final ProductModel? product;
  const _ProductFormDialog({this.product});

  @override
  ConsumerState<_ProductFormDialog> createState() =>
      _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _salePriceCtrl;
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _alertCtrl;
  String? _categoryId;
  String? _warehouseId;
  bool _loading = false;
  String? _error;
  List<CategoryModel> _categories = [];
  List<WarehouseModel> _warehouses = [];

  // Produit composé (ex: "Caisse" = 12 x "Boîte")
  bool _isComposite = false;
  String? _componentProductId;
  String? _componentProductName;
  late final TextEditingController _componentQtyCtrl;

  Uint8List? _imageBytes;
  String? _imageFilename;

  bool get isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product?.name ?? '');
    _barcodeCtrl =
        TextEditingController(text: widget.product?.barcode ?? '');
    _descCtrl =
        TextEditingController(text: widget.product?.description ?? '');
    _salePriceCtrl = TextEditingController(
        text: widget.product?.salePrice.toString() ?? '0');
    _purchasePriceCtrl = TextEditingController(
        text: widget.product?.purchasePrice.toString() ?? '0');
    _alertCtrl = TextEditingController(
        text: widget.product?.alertStock.toString() ?? '5');
    _categoryId = widget.product?.category?.id;
    _warehouseId = widget.product?.warehouseId;
    _isComposite = widget.product?.isComposite ?? false;
    _componentProductId = widget.product?.componentProductId;
    _componentQtyCtrl = TextEditingController(
        text: widget.product?.componentQuantity?.toString() ?? '');
    _loadData();
    if (_componentProductId != null) _resolveComponentName();
  }

  Future<void> _resolveComponentName() async {
    try {
      final all = await _fetchAllProductsForPicker();
      final match = all.where((p) => p.id == _componentProductId);
      if (match.isNotEmpty && mounted) {
        setState(() => _componentProductName = match.first.name);
      }
    } catch (_) {}
  }

  Future<void> _pickComponentProduct() async {
    final result = await showDialog<ProductModel>(
      context: context,
      builder: (_) => _SingleProductPickerDialog(excludeId: widget.product?.id),
    );
    if (result != null) {
      setState(() {
        _componentProductId = result.id;
        _componentProductName = result.name;
      });
    }
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ProductRepository().getCategories(),
        WarehouseRepository().listWarehouses(),
      ]);
      if (mounted) {
        setState(() {
          _categories = results[0] as List<CategoryModel>;
          _warehouses = results[1] as List<WarehouseModel>;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null || !mounted) return;
    setState(() {
      _imageBytes = file.bytes;
      _imageFilename = file.name;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _descCtrl.dispose();
    _salePriceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _alertCtrl.dispose();
    _componentQtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEdit ? 'Modifier le produit' : 'Nouveau produit'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ImagePickerSection(
                  existingUrl: widget.product?.imageUrl,
                  selectedBytes: _imageBytes,
                  onPick: _pickImage,
                  onRemove: () => setState(() {
                    _imageBytes = null;
                    _imageFilename = null;
                  }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nom *'),
                  validator: (v) => v!.isEmpty ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcodeCtrl,
                  decoration: const InputDecoration(labelText: 'Code-barres'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description (optionnel)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: _categories
                      .map((c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                if (_warehouses.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _warehouseId,
                    decoration: const InputDecoration(
                      labelText: 'Dépôt (optionnel)',
                      prefixIcon: Icon(Icons.warehouse_outlined, size: 18),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— Tous les dépôts —')),
                      ..._warehouses.map((w) => DropdownMenuItem(
                            value: w.id,
                            child: Row(
                              children: [
                                Text(w.name),
                                if (w.isDefault) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('défaut',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.primary)),
                                  ),
                                ],
                              ],
                            ),
                          )),
                    ],
                    onChanged: (v) => setState(() => _warehouseId = v),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _purchasePriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Prix achat *'),
                        validator: (v) => v!.isEmpty ? 'Requis' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _salePriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Prix vente *'),
                        validator: (v) => v!.isEmpty ? 'Requis' : null,
                      ),
                    ),
                  ],
                ),
                if (isEdit) ...[
                  const SizedBox(height: 12),
                  _WarehousePricesSection(productId: widget.product!.id),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _alertCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Seuil d\'alerte stock'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Produit composé'),
                  subtitle: const Text(
                    'Ex: "Caisse" = 12 x "Boîte" — le stock réel est suivi sur '
                    'le produit choisi, pas sur celui-ci.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _isComposite,
                  onChanged: (v) => setState(() {
                    _isComposite = v;
                    if (!v) {
                      _componentProductId = null;
                      _componentProductName = null;
                      _componentQtyCtrl.clear();
                    }
                  }),
                ),
                if (_isComposite) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickComponentProduct,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Produit composant *',
                        suffixIcon: Icon(Icons.search),
                      ),
                      child: Text(
                        _componentProductName ?? 'Choisir un produit',
                        style: TextStyle(
                          color: _componentProductName == null
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _componentQtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Quantité par unité *',
                      helperText: 'Ex: 12 → 1 "Caisse" = 12 unités de stock du composant',
                    ),
                    validator: (v) {
                      if (!_isComposite) return null;
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Invalide';
                      return null;
                    },
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 8),
              ],
            ),
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
              : Text(isEdit ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isComposite && _componentProductId == null) {
      setState(() => _error = 'Choisissez le produit composant');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final ProductModel saved;
    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'barcode': _barcodeCtrl.text.trim().isEmpty
            ? null
            : _barcodeCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'category_id': _categoryId,
        'sale_price': double.tryParse(_salePriceCtrl.text) ?? 0,
        'purchase_price': double.tryParse(_purchasePriceCtrl.text) ?? 0,
        'alert_stock': int.tryParse(_alertCtrl.text) ?? 5,
        'warehouse_id': _warehouseId,
        'component_product_id': _isComposite ? _componentProductId : null,
        'component_quantity':
            _isComposite ? double.tryParse(_componentQtyCtrl.text) : null,
      };
      final repo = ProductRepository();
      if (isEdit) {
        saved = await repo.updateProduct(widget.product!.id, data);
      } else {
        saved = await repo.createProduct(data);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Erreur lors de l\'enregistrement. Réessayez.';
      });
      return;
    }

    if (_imageBytes != null && _imageFilename != null) {
      try {
        await ProductRepository()
            .uploadProductImage(saved.id, _imageBytes!, _imageFilename!);
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Produit enregistré, mais l\'image n\'a pas pu être uploadée. Réessayez.';
          });
        }
        ref.invalidate(productsProvider);
        return;
      }
    }

    ref.invalidate(productsProvider);
    if (mounted) Navigator.pop(context);
  }
}

// ─── Prix par dépôt ───────────────────────────────────────────────────────

class _WarehousePricesSection extends StatefulWidget {
  final String productId;
  const _WarehousePricesSection({required this.productId});

  @override
  State<_WarehousePricesSection> createState() => _WarehousePricesSectionState();
}

class _WarehousePricesSectionState extends State<_WarehousePricesSection> {
  List<WarehousePriceModel>? _prices;
  final Map<String, TextEditingController> _ctrls = {};
  bool _loading = true;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prices = await ProductRepository().getWarehousePrices(widget.productId);
      if (!mounted) return;
      setState(() {
        _prices = prices;
        for (final p in prices) {
          _ctrls[p.warehouseId] =
              TextEditingController(text: p.salePrice?.toStringAsFixed(2) ?? '');
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String warehouseId) async {
    final text = _ctrls[warehouseId]!.text.trim();
    setState(() => _saving.add(warehouseId));
    try {
      if (text.isEmpty) {
        await ProductRepository().deleteWarehousePrice(widget.productId, warehouseId);
      } else {
        final price = double.tryParse(text.replaceAll(',', '.'));
        if (price == null || price <= 0) {
          if (mounted) setState(() => _saving.remove(warehouseId));
          return;
        }
        await ProductRepository().setWarehousePrice(widget.productId, warehouseId, price);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Prix mis à jour'),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur lors de la mise à jour du prix'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving.remove(warehouseId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final prices = _prices ?? [];
    if (prices.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Prix par dépôt',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const Text(
          'Laissez vide pour utiliser le prix de vente par défaut.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        ...prices.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                      child: Text(p.warehouseName,
                          style: const TextStyle(fontSize: 13))),
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: _ctrls[p.warehouseId],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        hintText: 'défaut',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _saving.contains(p.warehouseId)
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                          tooltip: 'Enregistrer',
                          onPressed: () => _save(p.warehouseId),
                        ),
                ],
              ),
            )),
      ],
    );
  }
}

// ─── Sélecteur de produit unique (produit composant) ─────────────────────────

class _SingleProductPickerDialog extends StatefulWidget {
  final String? excludeId;

  const _SingleProductPickerDialog({this.excludeId});

  @override
  State<_SingleProductPickerDialog> createState() => _SingleProductPickerDialogState();
}

class _SingleProductPickerDialogState extends State<_SingleProductPickerDialog> {
  List<ProductModel> _all = [];
  String _search = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _fetchAllProductsForPicker();
      if (!mounted) return;
      setState(() {
        // Un produit composé ne peut pas lui-même être composant (évite les
        // chaînes/cycles) ; on exclut aussi le produit en cours d'édition.
        _all = all
            .where((p) => p.id != widget.excludeId && !p.isComposite)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = extractAnyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? _all
        : _all.where((p) => p.name.toLowerCase().contains(_search.toLowerCase())).toList();

    return AlertDialog(
      title: const Text('Choisir le produit composant'),
      content: SizedBox(
        width: 440,
        height: 440,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Rechercher un produit',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const Divider(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
                      : filtered.isEmpty
                          ? const Center(child: Text('Aucun produit trouvé'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final p = filtered[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(p.name),
                                  subtitle: Text('Stock: ${p.stock ?? 0}'),
                                  onTap: () => Navigator.pop(context, p),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      ],
    );
  }
}

// ─── Image Picker Section ─────────────────────────────────────────────────────

class _ImagePickerSection extends StatelessWidget {
  final String? existingUrl;
  final Uint8List? selectedBytes;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ImagePickerSection({
    this.existingUrl,
    this.selectedBytes,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Image du produit',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildPreview(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onPick,
                      icon: const Icon(Icons.upload_rounded, size: 16),
                      label: const Text('Choisir une image'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 36)),
                    ),
                    if (selectedBytes != null) ...[
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: onRemove,
                        icon: const Icon(Icons.close_rounded,
                            size: 14, color: AppColors.error),
                        label: const Text('Retirer',
                            style: TextStyle(
                                color: AppColors.error, fontSize: 12)),
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28)),
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Text('JPG, PNG ou WebP',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    const size = 72.0;
    if (selectedBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(selectedBytes!,
            width: size, height: size, fit: BoxFit.cover),
      );
    }
    if (existingUrl != null && existingUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: _imgUrl(existingUrl!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _emptyPreview(size),
          errorWidget: (_, __, ___) => _emptyPreview(size),
        ),
      );
    }
    return _emptyPreview(size);
  }

  Widget _emptyPreview(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: const Icon(Icons.image_outlined,
            color: AppColors.textSecondary, size: 28),
      );
}

// ─── Category Manager ─────────────────────────────────────────────────────────

class _CategoryManagerDialog extends StatefulWidget {
  const _CategoryManagerDialog();

  @override
  State<_CategoryManagerDialog> createState() =>
      _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<_CategoryManagerDialog> {
  List<CategoryModel> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cats = await ProductRepository().getCategories();
      if (mounted)
        setState(() {
          _categories = cats;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.category_rounded, color: AppColors.primary, size: 20),
          SizedBox(width: 8),
          Flexible(child: Text('Gérer les catégories')),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: () => _showForm(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nouvelle catégorie'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40)),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!,
                  style: const TextStyle(color: AppColors.error)),
            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: _categories.isEmpty
                    ? const Center(
                        child: Text('Aucune catégorie',
                            style: TextStyle(
                                color: AppColors.textSecondary)))
                    : ListView.separated(
                        itemCount: _categories.length,
                        separatorBuilder: (ctx, i) =>
                            const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final cat = _categories[i];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.label_rounded,
                                  color: AppColors.primary, size: 16),
                            ),
                            title: Text(cat.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 16,
                                      color: AppColors.textSecondary),
                                  tooltip: 'Modifier',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                  onPressed: () =>
                                      _showForm(context, cat),
                                ),
                                IconButton(
                                  icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: AppColors.error),
                                  tooltip: 'Supprimer',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                  onPressed: () =>
                                      _confirmDelete(context, cat),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer')),
      ],
    );
  }

  void _showForm(BuildContext context, [CategoryModel? cat]) {
    final nameCtrl = TextEditingController(text: cat?.name ?? '');
    final descCtrl = TextEditingController(text: cat?.description ?? '');
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cat == null ? 'Nouvelle catégorie' : 'Modifier'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom de la catégorie *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optionnel)',
                  hintText: 'Ex : Boissons gazeuses et jus',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final desc = descCtrl.text.trim();
              Navigator.pop(ctx);
              try {
                final repo = ProductRepository();
                final payload = {
                  'name': name,
                  if (desc.isNotEmpty) 'description': desc,
                };
                if (cat == null) {
                  await repo.createCategory(payload);
                } else {
                  await repo.updateCategory(cat.id, payload);
                }
                _load();
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('Erreur : ${extractAnyError(e)}'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: Text(cat == null ? 'Créer' : 'Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, CategoryModel cat) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la catégorie ?'),
        content: SizedBox(
          width: double.maxFinite,
          child: Text(
              'Voulez-vous supprimer "${cat.name}" ? Les produits liés seront affectés.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ProductRepository().deleteCategory(cat.id);
                _load();
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('Erreur : ${extractAnyError(e)}'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

// ─── Adjust Stock Dialog ──────────────────────────────────────────────────────

class _AdjustStockDialog extends ConsumerStatefulWidget {
  final ProductModel product;
  const _AdjustStockDialog({required this.product});

  @override
  ConsumerState<_AdjustStockDialog> createState() => _AdjustStockDialogState();
}

class _AdjustStockDialogState extends ConsumerState<_AdjustStockDialog> {
  final _qtyCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _componentName;

  @override
  void initState() {
    super.initState();
    _qtyCtrl.addListener(() => setState(() {}));
    if (widget.product.isComposite) _resolveComponentName();
  }

  String _fmtQty(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  Future<void> _resolveComponentName() async {
    try {
      final all = await _fetchAllProductsForPicker();
      final match = all.where((p) => p.id == widget.product.componentProductId);
      if (match.isNotEmpty && mounted) {
        setState(() => _componentName = match.first.name);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.product.stock ?? 0;
    final qty = double.tryParse(_qtyCtrl.text.replaceAll('+', '').trim());
    final componentQty = widget.product.componentQuantity;
    final showConversion = widget.product.isComposite && qty != null && qty != 0 && componentQty != null;
    return AlertDialog(
      title: Text('Ajuster stock — ${widget.product.name}'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock actuel : $current',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            if (widget.product.isComposite) ...[
              const SizedBox(height: 4),
              Text(
                'Produit composé — le stock réel sera ajusté sur '
                '${_componentName ?? "le produit composant"}.',
                style: const TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantité à ajouter / retirer',
                hintText: 'ex: +10 ou -5',
              ),
            ),
            if (showConversion) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync_alt_rounded, size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${qty > 0 ? "+" : ""}${_fmtQty(qty)} ${widget.product.name} '
                        '→ ${qty > 0 ? "+" : ""}${_fmtQty(qty * componentQty)} '
                        '${_componentName ?? "produit composant"}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Raison (optionnel)',
                hintText: 'Inventaire, correction, perte...',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Confirmer'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qtyCtrl.text.replaceAll('+', '').trim());
    if (qty == null || qty == 0) {
      setState(() => _error = 'Entrez une quantité valide (ex: 10 ou -5)');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ProductRepository().adjustStock(
        widget.product.id, qty, reason: _reasonCtrl.text.trim(),
        warehouseId: ref.read(activeWarehouseProvider)?.id,
      );
      ref.invalidate(productsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Erreur lors de l\'ajustement. Réessayez.';
      });
    }
  }
}

// ─── Modifier Manager Dialog ──────────────────────────────────────────────────

class _ModifierManagerDialog extends StatefulWidget {
  const _ModifierManagerDialog();

  @override
  State<_ModifierManagerDialog> createState() => _ModifierManagerDialogState();
}

class _ModifierManagerDialogState extends State<_ModifierManagerDialog> {
  List<ModifierGroupModel> _groups = [];
  List<CategoryModel> _categories = [];
  List<MenuItemModel> _menuItems = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final repo = RestaurantRepository();
      final prodRepo = ProductRepository();
      final results = await Future.wait([
        repo.getModifierGroups(),
        prodRepo.getCategories(),
        repo.getMenuItems(),
      ]);
      if (mounted) {
        setState(() {
          _groups    = results[0] as List<ModifierGroupModel>;
          _categories = results[1] as List<CategoryModel>;
          _menuItems  = results[2] as List<MenuItemModel>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _scopeLabel(ModifierGroupModel g) {
    if (g.categoryId != null) {
      final cat = _categories.where((c) => c.id == g.categoryId).firstOrNull;
      return 'Catégorie: ${cat?.name ?? g.categoryId}';
    }
    if (g.menuItemId != null) {
      final item = _menuItems.where((m) => m.id == g.menuItemId).firstOrNull;
      return 'Plat: ${item?.name ?? g.menuItemId}';
    }
    return 'Global';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
          SizedBox(width: 8),
          Flexible(child: Text('Gérer les modificateurs')),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: () => _showGroupForm(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nouveau groupe'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40)),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: _groups.isEmpty
                    ? const Center(
                        child: Text('Aucun groupe de modificateurs',
                            style: TextStyle(color: AppColors.textSecondary)))
                    : ListView.separated(
                        itemCount: _groups.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final g = _groups[i];
                          return ExpansionTile(
                            dense: true,
                            tilePadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 0),
                            leading: Icon(
                              g.multiSelect
                                  ? Icons.check_box_outlined
                                  : Icons.radio_button_checked_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                            title: Text(g.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text(
                              '${_scopeLabel(g)} · ${g.required ? "Requis" : "Optionnel"} · ${g.multiSelect ? "Multi" : "Un seul"}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textSecondary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 16,
                                      color: AppColors.textSecondary),
                                  tooltip: 'Modifier',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                  onPressed: () => _showGroupForm(context, g),
                                ),
                                IconButton(
                                  icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: AppColors.error),
                                  tooltip: 'Supprimer',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                  onPressed: () =>
                                      _confirmDeleteGroup(context, g),
                                ),
                                const Icon(Icons.expand_more_rounded,
                                    size: 18,
                                    color: AppColors.textSecondary),
                              ],
                            ),
                            children: [
                              // Options list
                              ...g.options.map((opt) => ListTile(
                                    dense: true,
                                    contentPadding:
                                        const EdgeInsets.only(left: 48, right: 8),
                                    title: Text(opt.name,
                                        style:
                                            const TextStyle(fontSize: 12)),
                                    subtitle: opt.extraPrice > 0
                                        ? Text(
                                            '+${opt.extraPrice.toStringAsFixed(0)} HTG',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.primary))
                                        : null,
                                    trailing: IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 14,
                                          color: AppColors.error),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 28, minHeight: 28),
                                      onPressed: () =>
                                          _deleteOption(g.id, opt.id),
                                    ),
                                  )),
                              // Add option row
                              Padding(
                                padding: const EdgeInsets.fromLTRB(48, 4, 12, 8),
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _showOptionForm(context, g.id),
                                  icon: const Icon(Icons.add_rounded, size: 14),
                                  label: const Text('Ajouter une option',
                                      style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer')),
      ],
    );
  }

  void _showGroupForm(BuildContext context, [ModifierGroupModel? g]) {
    final nameCtrl = TextEditingController(text: g?.name ?? '');
    bool required = g?.required ?? false;
    bool multiSelect = g?.multiSelect ?? true;
    String? selectedCatId = g?.categoryId;
    String? selectedMenuItemId = g?.menuItemId;
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(g == null ? 'Nouveau groupe' : 'Modifier le groupe'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Nom du groupe *'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Lié à',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: selectedCatId,
                    decoration:
                        const InputDecoration(labelText: 'Catégorie (optionnel)'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— Aucune —')),
                      ..._categories.map((c) => DropdownMenuItem(
                          value: c.id, child: Text(c.name))),
                    ],
                    onChanged: (v) => setInner(() {
                      selectedCatId = v;
                      if (v != null) selectedMenuItemId = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: selectedMenuItemId,
                    decoration:
                        const InputDecoration(labelText: 'Menu / Plat (optionnel)'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— Aucun —')),
                      ..._menuItems.map((m) => DropdownMenuItem(
                          value: m.id, child: Text(m.name))),
                    ],
                    onChanged: (v) => setInner(() {
                      selectedMenuItemId = v;
                      if (v != null) selectedCatId = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Obligatoire',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Le client doit faire un choix',
                        style: TextStyle(fontSize: 11)),
                    value: required,
                    onChanged: (v) => setInner(() => required = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sélection multiple',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                        'Cases à cocher (sinon boutons radio)',
                        style: TextStyle(fontSize: 11)),
                    value: multiSelect,
                    onChanged: (v) => setInner(() => multiSelect = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final repo = RestaurantRepository();
                  if (g == null) {
                    await repo.createModifierGroup(
                      name: name,
                      categoryId: selectedCatId,
                      menuItemId: selectedMenuItemId,
                      required: required,
                      multiSelect: multiSelect,
                    );
                  } else {
                    await repo.updateModifierGroup(g.id,
                      name: name,
                      categoryId: selectedCatId,
                      menuItemId: selectedMenuItemId,
                      required: required,
                      multiSelect: multiSelect,
                    );
                  }
                  _load();
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(SnackBar(
                      content: Text('Erreur : ${extractAnyError(e)}'),
                      backgroundColor: AppColors.error,
                    ));
                  }
                }
              },
              child: Text(g == null ? 'Créer' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionForm(BuildContext context, String groupId) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle option'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Supplément (HTG)',
                    hintText: '0'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final price =
                  double.tryParse(priceCtrl.text.trim()) ?? 0.0;
              Navigator.pop(ctx);
              try {
                await RestaurantRepository().addOption(groupId, name, price);
                _load();
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('Erreur : ${extractAnyError(e)}'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOption(String groupId, String optionId) async {
    try {
      await RestaurantRepository().deleteOption(groupId, optionId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : ${extractAnyError(e)}'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  void _confirmDeleteGroup(BuildContext context, ModifierGroupModel g) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le groupe ?'),
        content: Text(
            'Supprimer "${g.name}" et toutes ses options ? Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await RestaurantRepository().deleteModifierGroup(g.id);
                _load();
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('Erreur : ${extractAnyError(e)}'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
