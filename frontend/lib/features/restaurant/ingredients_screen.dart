import 'package:flutter/material.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/product_repository.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';

class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  final _repo = RestaurantRepository();
  final _prodRepo = ProductRepository();

  List<IngredientModel> _ingredients = [];
  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repo.getIngredients(),
        _prodRepo.getProducts(limit: 200),
        _prodRepo.getCategories(),
      ]);
      if (mounted) {
        setState(() {
          _ingredients = results[0] as List<IngredientModel>;
          _products = (results[1] as dynamic).data as List<ProductModel>;
          _categories = results[2] as List<CategoryModel>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  void _showForm([IngredientModel? existing]) {
    showDialog(
      context: context,
      builder: (_) => _IngredientFormDialog(
        existing: existing,
        products: _products,
        categories: _categories,
        onSave: (name, productId, categoryId) async {
          try {
            if (existing == null) {
              await _repo.createIngredient(
                  name: name,
                  productId: productId,
                  categoryId: categoryId);
            } else {
              await _repo.updateIngredient(existing.id,
                  name: name,
                  productId: productId,
                  categoryId: categoryId);
            }
            await _load();
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(extractAnyError(e)),
                backgroundColor: AppColors.error,
              ));
            }
          }
        },
      ),
    );
  }

  void _confirmDelete(IngredientModel ing) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l\'ingrédient ?'),
        content: Text('« ${ing.name} » sera supprimé définitivement.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _repo.deleteIngredient(ing.id);
                await _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(extractAnyError(e)),
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

  String _scopeLabel(IngredientModel ing) {
    if (ing.productId != null) {
      final p =
          _products.where((x) => x.id == ing.productId).firstOrNull;
      return p != null ? 'Produit : ${p.name}' : 'Produit';
    }
    if (ing.categoryId != null) {
      final c =
          _categories.where((x) => x.id == ing.categoryId).firstOrNull;
      return c != null ? 'Catégorie : ${c.name}' : 'Catégorie';
    }
    return 'Global';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Ingrédients & options',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvel ingrédient'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ingredients.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.egg_outlined,
                          size: 56, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      const Text('Aucun ingrédient configuré',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text(
                        'Associez des ingrédients à une catégorie\nou à un produit spécifique.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _showForm(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Ajouter un ingrédient'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _ingredients.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final ing = _ingredients[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.divider),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                              Icons.restaurant_menu_rounded,
                              color: AppColors.primary,
                              size: 20),
                        ),
                        title: Text(ing.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          _scopeLabel(ing),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_rounded,
                                  size: 18,
                                  color: AppColors.textSecondary),
                              onPressed: () => _showForm(ing),
                              tooltip: 'Modifier',
                            ),
                            IconButton(
                              icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: AppColors.error),
                              onPressed: () => _confirmDelete(ing),
                              tooltip: 'Supprimer',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ── Form dialog ───────────────────────────────────────────────────────────────

class _IngredientFormDialog extends StatefulWidget {
  final IngredientModel? existing;
  final List<ProductModel> products;
  final List<CategoryModel> categories;
  final Future<void> Function(String name, String? productId,
      String? categoryId) onSave;

  const _IngredientFormDialog({
    this.existing,
    required this.products,
    required this.categories,
    required this.onSave,
  });

  @override
  State<_IngredientFormDialog> createState() =>
      _IngredientFormDialogState();
}

class _IngredientFormDialogState extends State<_IngredientFormDialog> {
  final _nameCtrl = TextEditingController();
  // scope: 'none' | 'product' | 'category'
  String _scope = 'none';
  String? _productId;
  String? _categoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ing = widget.existing;
    if (ing != null) {
      _nameCtrl.text = ing.name;
      if (ing.productId != null) {
        _scope = 'product';
        _productId = ing.productId;
      } else if (ing.categoryId != null) {
        _scope = 'category';
        _categoryId = ing.categoryId;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        name,
        _scope == 'product' ? _productId : null,
        _scope == 'category' ? _categoryId : null,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Nouvel ingrédient'
          : 'Modifier l\'ingrédient'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom de l\'ingrédient *',
                hintText: 'Ex: Fromage, Oignons, Basilic…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Associer à',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    fontSize: 13)),
            const SizedBox(height: 8),
            // Scope radio
            _ScopeOption(
              value: 'none',
              groupValue: _scope,
              label: 'Aucun (global)',
              onChanged: (v) => setState(() {
                _scope = v!;
              }),
            ),
            _ScopeOption(
              value: 'category',
              groupValue: _scope,
              label: 'Une catégorie',
              onChanged: (v) => setState(() {
                _scope = v!;
              }),
            ),
            if (_scope == 'category') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Catégorie',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                items: widget.categories
                    .map((c) => DropdownMenuItem(
                        value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            _ScopeOption(
              value: 'product',
              groupValue: _scope,
              label: 'Un produit spécifique',
              onChanged: (v) => setState(() {
                _scope = v!;
              }),
            ),
            if (_scope == 'product') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _productId,
                decoration: const InputDecoration(
                  labelText: 'Produit',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                items: widget.products
                    .map((p) => DropdownMenuItem(
                        value: p.id, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() => _productId = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ||
                  _nameCtrl.text.trim().isEmpty ||
                  (_scope == 'product' && _productId == null) ||
                  (_scope == 'category' && _categoryId == null)
              ? null
              : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(widget.existing == null ? 'Créer' : 'Enregistrer'),
        ),
      ],
    );
  }
}

class _ScopeOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final String label;
  final ValueChanged<String?> onChanged;

  const _ScopeOption({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: value,
      groupValue: groupValue,
      title:
          Text(label, style: const TextStyle(fontSize: 13)),
      activeColor: AppColors.primary,
      onChanged: onChanged,
    );
  }
}
