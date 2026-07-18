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

final _fmt =
    NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);

String _imgUrl(String path) => '${dio.options.baseUrl}$path';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return Column(
      children: [
        const _ProductsToolbar(),
        const Divider(height: 1),
        Expanded(
          child: productsAsync.when(
            data: (products) {
              if (products.data.isEmpty) {
                return const Center(
                    child: Text('Aucun produit trouvé',
                        style: TextStyle(color: AppColors.textSecondary)));
              }
              final isWide = MediaQuery.sizeOf(context).width >= 700;
              if (isWide) return _ProductTable(products: products.data);
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: products.data.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) =>
                    _ProductCard(product: products.data[i]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Erreur: $e',
                    style: const TextStyle(color: AppColors.error))),
          ),
        ),
      ],
    );
  }
}

// ─── Toolbar ─────────────────────────────────────────────────────────────────

class _ProductsToolbar extends ConsumerWidget {
  const _ProductsToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = context.isMobile;
    final canCreate = ref.watch(hasPermissionProvider(Perm.productsCreate));
    final canManageCat = ref.watch(hasPermissionProvider(Perm.productsUpdate));

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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.background),
            columns: [
              const DataColumn(label: Text('')),
              const DataColumn(label: Text('Produit')),
              const DataColumn(label: Text('Catégorie')),
              const DataColumn(label: Text('Prix achat'), numeric: true),
              const DataColumn(label: Text('Prix vente'), numeric: true),
              const DataColumn(label: Text('Stock')),
              const DataColumn(label: Text('Seuil alerte'), numeric: true),
              if (canEdit) const DataColumn(label: Text('')),
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
                DataCell(_StockChip(product: p)),
                DataCell(Text('${p.alertStock}',
                    style: const TextStyle(fontSize: 13))),
                if (canEdit)
                  DataCell(IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _ProductFormDialog(product: p),
                    ),
                  )),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
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

// ─── Card (mobile) ────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
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
              Text('Stock: ${product.stock}',
                  style: TextStyle(
                      fontSize: 12,
                      color: product.isLowStock
                          ? AppColors.error
                          : AppColors.textSecondary)),
          ],
        ),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _ProductFormDialog(product: product),
        ),
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
  late final TextEditingController _salePriceCtrl;
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _alertCtrl;
  String? _categoryId;
  bool _loading = false;
  String? _error;
  List<CategoryModel> _categories = [];

  Uint8List? _imageBytes;
  String? _imageFilename;

  bool get isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product?.name ?? '');
    _barcodeCtrl =
        TextEditingController(text: widget.product?.barcode ?? '');
    _salePriceCtrl = TextEditingController(
        text: widget.product?.salePrice.toString() ?? '0');
    _purchasePriceCtrl = TextEditingController(
        text: widget.product?.purchasePrice.toString() ?? '0');
    _alertCtrl = TextEditingController(
        text: widget.product?.alertStock.toString() ?? '5');
    _categoryId = widget.product?.category?.id;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ProductRepository().getCategories();
      if (mounted) setState(() => _categories = cats);
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
    _salePriceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _alertCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEdit ? 'Modifier le produit' : 'Nouveau produit'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: double.maxFinite,
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
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: _categories
                      .map((c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _alertCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Seuil d\'alerte stock'),
                ),
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
        'category_id': _categoryId,
        'sale_price': double.tryParse(_salePriceCtrl.text) ?? 0,
        'purchase_price': double.tryParse(_purchasePriceCtrl.text) ?? 0,
        'alert_stock': int.tryParse(_alertCtrl.text) ?? 5,
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
        width: double.maxFinite,
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
          width: double.maxFinite,
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
                    content: Text('Erreur : $e'),
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
                    content: Text('Erreur : $e'),
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
