import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/discount_model.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/repositories/discount_repository.dart';
import 'package:pos_connect/data/repositories/product_repository.dart';
import 'package:pos_connect/providers/discount_provider.dart';

const List<String> _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// /api/products/ plafonne per_page à 100 (Query(..., le=100)) — on pagine
/// pour récupérer tout le catalogue au lieu d'envoyer une limite invalide.
Future<List<ProductModel>> _fetchAllProducts() async {
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

String _formatValue(DiscountModel d) =>
    d.isPercentage ? '${d.value.toStringAsFixed(0)}%' : '${d.value.toStringAsFixed(0)} HTG';

String _formatScope(String scope) {
  switch (scope) {
    case 'receipt':
      return 'Ticket entier';
    case 'item':
      return 'Article';
    default:
      return 'Ticket + article';
  }
}

const List<String> _dayAbbr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

String _formatTimeHm(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final parts = raw.split(':');
  if (parts.length < 2) return raw;
  return '${parts[0]}:${parts[1]}';
}

/// Décrit les conditions d'un rabais automatique : jours + plage horaire.
String _formatSchedule(DiscountModel d) {
  final days = d.scheduleDays
      ?.split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .where((i) => i >= 0 && i < 7)
      .toList();
  final daysLabel = (days == null || days.isEmpty || days.length == 7)
      ? 'Tous les jours'
      : (days..sort()).map((i) => _dayAbbr[i]).join(', ');

  final hasStart = d.scheduleStart != null && d.scheduleStart!.isNotEmpty;
  final hasEnd = d.scheduleEnd != null && d.scheduleEnd!.isNotEmpty;
  if (!hasStart && !hasEnd) return daysLabel;

  final start = hasStart ? _formatTimeHm(d.scheduleStart) : '00:00';
  final end = hasEnd ? _formatTimeHm(d.scheduleEnd) : '23:59';
  return '$daysLabel · $start–$end';
}

class DiscountsScreen extends ConsumerWidget {
  const DiscountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discountsAsync = ref.watch(discountsProvider);

    return Column(
      children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text('Rabais',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _DiscountFormDialog(),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nouveau rabais'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: discountsAsync.when(
            data: (discounts) => discounts.isEmpty
                ? const Center(
                    child: Text('Aucun rabais configuré',
                        style: TextStyle(color: AppColors.textSecondary)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: discounts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _DiscountCard(discount: discounts[i]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Erreur: ${extractAnyError(e)}',
                    style: const TextStyle(color: AppColors.error))),
          ),
        ),
      ],
    );
  }
}

class _DiscountCard extends ConsumerWidget {
  final DiscountModel discount;

  const _DiscountCard({required this.discount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.sell_outlined, color: AppColors.success, size: 22),
        ),
        title: Text(discount.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_formatValue(discount)} — ${_formatScope(discount.scope)}',
                style: const TextStyle(fontSize: 12)),
            if (discount.minQuantity != null && discount.minQuantity! > 0)
              Text(
                  'À partir de ${discount.minQuantity!.toStringAsFixed(discount.minQuantity! % 1 == 0 ? 0 : 2)} unité(s)',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            if (discount.isLinkedToProducts)
              Text(
                  '${discount.productIds.length} produit(s) lié(s) — suggestion automatique en caisse',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            if (discount.isAutomatic)
              Text('Automatique — ${_formatSchedule(discount)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            if (!discount.isActive)
              const Text('Désactivé',
                  style: TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 18),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _DiscountFormDialog(discount: discount),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Supprimer ce rabais ?'),
                    content: Text('« ${discount.name} » ne sera plus disponible en caisse.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler')),
                      ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Supprimer')),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    await DiscountRepository().deleteDiscount(discount.id);
                    ref.invalidate(discountsProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(extractAnyError(e))),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscountFormDialog extends ConsumerStatefulWidget {
  final DiscountModel? discount;

  const _DiscountFormDialog({this.discount});

  @override
  ConsumerState<_DiscountFormDialog> createState() => _DiscountFormDialogState();
}

class _DiscountFormDialogState extends ConsumerState<_DiscountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _minQuantityCtrl;
  late String _type;
  late String _scope;
  late bool _isAutomatic;
  late bool _isActive;
  late Set<int> _selectedDays;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _loading = false;
  String? _error;
  // Produits liés — id -> nom (résolu au fur et à mesure pour l'affichage)
  final Map<String, String> _linkedProducts = {};

  bool get isEdit => widget.discount != null;

  @override
  void initState() {
    super.initState();
    final d = widget.discount;
    _nameCtrl = TextEditingController(text: d?.name ?? '');
    _valueCtrl = TextEditingController(text: d != null ? d.value.toString() : '');
    _minQuantityCtrl = TextEditingController(
        text: d?.minQuantity != null ? d!.minQuantity!.toString() : '');
    _type = d?.type ?? 'percentage';
    _scope = d?.scope ?? 'both';
    _isAutomatic = d?.isAutomatic ?? false;
    _isActive = d?.isActive ?? true;
    _selectedDays = d?.scheduleDays == null || d!.scheduleDays!.isEmpty
        ? {0, 1, 2, 3, 4, 5, 6}
        : d.scheduleDays!.split(',').map((s) => int.parse(s.trim())).toSet();
    _startTime = _parseTime(d?.scheduleStart);
    _endTime = _parseTime(d?.scheduleEnd);
    if (d != null && d.productIds.isNotEmpty) {
      for (final id in d.productIds) {
        _linkedProducts[id] = id; // nom résolu dès l'ouverture du sélecteur
      }
      _resolveLinkedProductNames();
    }
  }

  Future<void> _resolveLinkedProductNames() async {
    try {
      final all = await _fetchAllProducts();
      final byId = {for (final p in all) p.id: p.name};
      if (!mounted) return;
      setState(() {
        for (final id in _linkedProducts.keys.toList()) {
          if (byId.containsKey(id)) _linkedProducts[id] = byId[id]!;
        }
      });
    } catch (_) {
      // Affichage dégradé (ID brut) si la résolution échoue — non bloquant
    }
  }

  Future<void> _openProductPicker() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ProductPickerDialog(initiallySelected: Map.of(_linkedProducts)),
    );
    if (result != null) {
      setState(() {
        _linkedProducts
          ..clear()
          ..addAll(result);
      });
    }
  }

  TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    _minQuantityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEdit ? 'Modifier le rabais' : 'Nouveau rabais'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nom *'),
                  validator: (v) => v!.isEmpty ? 'Requis' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _type,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(value: 'percentage', child: Text('Pourcentage (%)')),
                          DropdownMenuItem(value: 'fixed', child: Text('Montant fixe')),
                        ],
                        onChanged: (v) => setState(() => _type = v ?? 'percentage'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _valueCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                            labelText: _type == 'percentage' ? 'Valeur (%)' : 'Valeur (HTG)'),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n <= 0) return 'Invalide';
                          if (_type == 'percentage' && n > 100) return 'Max 100%';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _scope,
                  decoration: const InputDecoration(labelText: 'Applicable à'),
                  items: const [
                    DropdownMenuItem(value: 'both', child: Text('Ticket entier + article')),
                    DropdownMenuItem(value: 'receipt', child: Text('Ticket entier seulement')),
                    DropdownMenuItem(value: 'item', child: Text('Article seulement')),
                  ],
                  onChanged: (v) => setState(() => _scope = v ?? 'both'),
                ),
                if (_scope == 'item' || _scope == 'both') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _minQuantityCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Quantité minimale (article) — optionnel',
                      helperText: 'Ex: 3 → le rabais ne s\'applique qu\'à partir de 3 unités',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = double.tryParse(v.trim());
                      if (n == null || n <= 0) return 'Invalide';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Produits liés — optionnel',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            const Text(
                              'Si renseigné, ce rabais n\'est plus sélectionnable manuellement — '
                              'il est suggéré automatiquement sur ces produits en caisse.',
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            if (_linkedProducts.isEmpty)
                              const Text('Aucun produit lié', style: TextStyle(fontSize: 12))
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _linkedProducts.entries
                                    .map((e) => Chip(
                                          label: Text(e.value, style: const TextStyle(fontSize: 12)),
                                          onDeleted: () =>
                                              setState(() => _linkedProducts.remove(e.key)),
                                        ))
                                    .toList(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _openProductPicker,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Produits'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Actif'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automatique (s\'applique sans action du caissier)'),
                  subtitle: const Text('Selon les jours et l\'heure ci-dessous',
                      style: TextStyle(fontSize: 12)),
                  value: _isAutomatic,
                  onChanged: (v) => setState(() => _isAutomatic = v),
                ),
                if (_isAutomatic) ...[
                  const SizedBox(height: 8),
                  const Text('Jours', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      final selected = _selectedDays.contains(i);
                      return FilterChip(
                        label: Text(_dayLabels[i]),
                        selected: selected,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selectedDays.add(i);
                          } else {
                            _selectedDays.remove(i);
                          }
                        }),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                                context: context, initialTime: _startTime ?? const TimeOfDay(hour: 0, minute: 0));
                            if (t != null) setState(() => _startTime = t);
                          },
                          child: Text(_startTime == null ? 'Heure début' : _formatTime(_startTime!)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                                context: context, initialTime: _endTime ?? const TimeOfDay(hour: 23, minute: 59));
                            if (t != null) setState(() => _endTime = t);
                          },
                          child: Text(_endTime == null ? 'Heure fin' : _formatTime(_endTime!)),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
    try {
      final allDays = _selectedDays.length >= 7;
      final data = {
        'name': _nameCtrl.text.trim(),
        'type': _type,
        'value': double.parse(_valueCtrl.text.trim()),
        'scope': _scope,
        'is_automatic': _isAutomatic,
        'is_active': _isActive,
        'schedule_days': _isAutomatic && !allDays
            ? (_selectedDays.toList()..sort()).join(',')
            : null,
        'schedule_start': _isAutomatic && _startTime != null ? _formatTime(_startTime!) : null,
        'schedule_end': _isAutomatic && _endTime != null ? _formatTime(_endTime!) : null,
        'min_quantity': (_scope == 'item' || _scope == 'both') && _minQuantityCtrl.text.trim().isNotEmpty
            ? double.tryParse(_minQuantityCtrl.text.trim())
            : null,
        'product_ids': (_scope == 'item' || _scope == 'both') && _linkedProducts.isNotEmpty
            ? _linkedProducts.keys.toList()
            : <String>[],
      };
      final repo = DiscountRepository();
      if (isEdit) {
        await repo.updateDiscount(widget.discount!.id, data);
      } else {
        await repo.createDiscount(data);
      }
      ref.invalidate(discountsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = extractAnyError(e);
      });
    }
  }
}

/// Sélecteur de produits — recherche + cases à cocher, renvoie une map
/// id -> nom des produits sélectionnés (ou null si annulé).
class _ProductPickerDialog extends StatefulWidget {
  final Map<String, String> initiallySelected;

  const _ProductPickerDialog({required this.initiallySelected});

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  late final Map<String, String> _selected;
  List<ProductModel> _all = [];
  String _search = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = Map.of(widget.initiallySelected);
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _fetchAllProducts();
      if (!mounted) return;
      setState(() {
        _all = all;
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
      title: const Text('Choisir les produits'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Rechercher un produit',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Text('${_selected.length} produit(s) sélectionné(s)',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
                                final checked = _selected.containsKey(p.id);
                                return CheckboxListTile(
                                  dense: true,
                                  title: Text(p.name),
                                  value: checked,
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _selected[p.id] = p.name;
                                    } else {
                                      _selected.remove(p.id);
                                    }
                                  }),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
