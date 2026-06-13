import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/inventory_model.dart';
import 'package:pos_connect/data/repositories/inventory_repository.dart';
import 'package:pos_connect/providers/inventory_provider.dart';

final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');
final _qtyFmt = NumberFormat('#,##0.##', 'fr');

enum _View { list, setup, count }

// ─── Count entry: wraps preview item + controller ──────────────────────────

class _CountEntry {
  final InventoryPreviewItem item;
  final TextEditingController ctrl;

  _CountEntry(this.item)
      : ctrl = TextEditingController(
            text: item.expectedQty % 1 == 0
                ? item.expectedQty.toInt().toString()
                : item.expectedQty.toStringAsFixed(2));

  double get counted => double.tryParse(ctrl.text) ?? 0;
  double get diff => counted - item.expectedQty;
  bool get hasDiscrepancy => diff.abs() > 0.001;

  void dispose() => ctrl.dispose();
}

// ─── Root screen ──────────────────────────────────────────────────────────────

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  _View _view = _View.list;

  // Setup state
  String _inventoryType = 'full';
  final List<String> _selectedCategoryIds = [];
  final _notesCtrl = TextEditingController();

  // Count state
  List<_CountEntry> _entries = [];
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _loadingPreview = false;
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _searchCtrl.dispose();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _goSetup() => setState(() {
        _view = _View.setup;
        _inventoryType = 'full';
        _selectedCategoryIds.clear();
        _notesCtrl.clear();
      });

  Future<void> _goCount() async {
    setState(() => _loadingPreview = true);
    try {
      final items = await InventoryRepository().getPreview(
        categoryIds:
            _inventoryType == 'partial' ? _selectedCategoryIds : null,
      );
      for (final e in _entries) {
        e.dispose();
      }
      setState(() {
        _entries = items.map((i) => _CountEntry(i)).toList();
        _view = _View.count;
        _searchQuery = '';
        _searchCtrl.clear();
        _submitError = null;
        _loadingPreview = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingPreview = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _backToList() {
    setState(() {
      _view = _View.list;
      _submitError = null;
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final discrepancies = _entries.where((e) => e.hasDiscrepancy).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Confirmer l\'inventaire'),
        content: Text(discrepancies == 0
            ? 'Aucun écart détecté. Confirmer l\'inventaire ?'
            : '$discrepancies écart(s) détecté(s). Les stocks seront ajustés automatiquement. Continuer ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final items = _entries
          .map((e) => {
                'product_id': e.item.productId,
                'counted_qty': e.counted,
              })
          .toList();

      final result = await InventoryRepository().createInventory(
        inventoryType: _inventoryType,
        categoryIds:
            _inventoryType == 'partial' ? _selectedCategoryIds : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        items: items,
      );

      ref.invalidate(inventoryListProvider);

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _view = _View.list;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${result['reference']} — ${result['discrepancy_count']} écart(s) ajusté(s)'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = e.toString();
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_view) {
      _View.list => _buildList(),
      _View.setup => _buildSetup(),
      _View.count => _buildCountSheet(),
    };
  }

  // ── VIEW: list ─────────────────────────────────────────────────────────────

  Widget _buildList() {
    final inventoriesAsync = ref.watch(inventoryListProvider);
    return Column(
      children: [
        // Toolbar
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text('Historique des inventaires',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _goSetup,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Nouvel inventaire'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: inventoriesAsync.when(
            data: (list) => list.isEmpty
                ? _emptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _InventoryCard(
                      record: list[i],
                      onDetail: () => _showDetail(list[i].id),
                    ),
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Erreur: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 56, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('Aucun inventaire effectué',
                style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 4),
            Text('Cliquez sur "Nouvel inventaire" pour commencer.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );

  void _showDetail(String id) {
    showDialog(
      context: context,
      builder: (ctx) => _InventoryDetailDialog(inventoryId: id),
    );
  }

  // ── VIEW: setup ────────────────────────────────────────────────────────────

  Widget _buildSetup() {
    final categoriesAsync = ref.watch(categoriesProvider);
    return Column(
      children: [
        // Header
        Container(
          color: AppColors.surface,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _backToList,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              const Text('Configurer l\'inventaire',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type selection
                const Text('Type d\'inventaire',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TypeCard(
                        icon: Icons.warehouse_rounded,
                        title: 'Inventaire complet',
                        subtitle: 'Tous les produits actifs',
                        selected: _inventoryType == 'full',
                        onTap: () =>
                            setState(() => _inventoryType = 'full'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TypeCard(
                        icon: Icons.filter_alt_rounded,
                        title: 'Inventaire partiel',
                        subtitle: 'Sélectionner par catégorie',
                        selected: _inventoryType == 'partial',
                        onTap: () =>
                            setState(() => _inventoryType = 'partial'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Category selection (only for partial)
                if (_inventoryType == 'partial') ...[
                  const Text('Catégories à inventorier',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 8),
                  categoriesAsync.when(
                    data: (cats) => cats.isEmpty
                        ? const Text('Aucune catégorie disponible',
                            style: TextStyle(
                                color: AppColors.textSecondary))
                        : Column(
                            children: cats
                                .map((cat) => CheckboxListTile(
                                      value: _selectedCategoryIds
                                          .contains(cat.id),
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selectedCategoryIds
                                                .add(cat.id);
                                          } else {
                                            _selectedCategoryIds
                                                .remove(cat.id);
                                          }
                                        });
                                      },
                                      title: Text(cat.name,
                                          style: const TextStyle(
                                              fontSize: 14)),
                                      activeColor: AppColors.primary,
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                    ))
                                .toList(),
                          ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erreur: $e',
                        style: const TextStyle(color: AppColors.error)),
                  ),
                  const SizedBox(height: 24),
                ],

                // Notes
                const Text('Notes (optionnel)',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Raison de l\'inventaire, observations...',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 32),

                // Action
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: (_loadingPreview ||
                            (_inventoryType == 'partial' &&
                                _selectedCategoryIds.isEmpty))
                        ? null
                        : _goCount,
                    icon: _loadingPreview
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.arrow_forward_rounded,
                            size: 18),
                    label: Text(_loadingPreview
                        ? 'Chargement...'
                        : 'Commencer le comptage'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── VIEW: count sheet ──────────────────────────────────────────────────────

  Widget _buildCountSheet() {
    final filtered = _searchQuery.isEmpty
        ? _entries
        : _entries
            .where((e) =>
                e.item.productName
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ||
                (e.item.barcode ?? '')
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()))
            .toList();

    final discrepancies = _entries.where((e) => e.hasDiscrepancy).length;

    return Column(
      children: [
        // Header
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _view = _View.setup),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _inventoryType == 'full'
                          ? 'Comptage — Inventaire complet'
                          : 'Comptage — Inventaire partiel',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      '${_entries.length} produit(s) • $discrepancies écart(s)',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed:
                    (_submitting || _entries.isEmpty) ? null : _submit,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent),
                icon: _submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_rounded, size: 16),
                label: const Text('Valider'),
              ),
            ],
          ),
        ),

        // Search bar
        Container(
          color: AppColors.surface,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Filtrer par produit ou code-barres...',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),

        // Column headers
        Container(
          color: AppColors.background,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: const [
              Expanded(
                  flex: 4,
                  child: Text('Produit',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary))),
              SizedBox(
                  width: 80,
                  child: Text('Système',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary))),
              SizedBox(
                  width: 100,
                  child: Text('Compté',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary))),
              SizedBox(
                  width: 70,
                  child: Text('Écart',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary))),
            ],
          ),
        ),
        const Divider(height: 1),

        if (_submitError != null)
          Container(
            margin: const EdgeInsets.all(12),
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
                  child: Text(_submitError!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 13))),
            ]),
          ),

        // Product rows
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('Aucun produit trouvé',
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16),
                  itemBuilder: (ctx, i) =>
                      _CountRow(entry: filtered[i], onChanged: () {
                    setState(() {}); // refresh diff column
                  }),
                ),
        ),
      ],
    );
  }
}

// ─── Type selection card ──────────────────────────────────────────────────────

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary,
                size: 28),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ─── Count row ────────────────────────────────────────────────────────────────

class _CountRow extends StatelessWidget {
  final _CountEntry entry;
  final VoidCallback onChanged;

  const _CountRow({required this.entry, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final diff = entry.diff;
    final Color diffColor;
    final String diffLabel;

    if (diff.abs() < 0.001) {
      diffColor = AppColors.textSecondary;
      diffLabel = '—';
    } else if (diff > 0) {
      diffColor = AppColors.accent;
      diffLabel = '+${_qtyFmt.format(diff)}';
    } else {
      diffColor = AppColors.error;
      diffLabel = _qtyFmt.format(diff);
    }

    return Container(
      color: entry.hasDiscrepancy
          ? (diff > 0
              ? AppColors.accent.withValues(alpha: 0.04)
              : AppColors.error.withValues(alpha: 0.04))
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.item.productName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
                Text(entry.item.category,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              _qtyFmt.format(entry.item.expectedQty),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(
            width: 100,
            child: TextField(
              controller: entry.ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              diffLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: diffColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Inventory card (list view) ───────────────────────────────────────────────

class _InventoryCard extends StatelessWidget {
  final InventoryModel record;
  final VoidCallback onDetail;

  const _InventoryCard({required this.record, required this.onDetail});

  @override
  Widget build(BuildContext context) {
    final isFull = record.inventoryType == 'full';
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.inventory_2_rounded,
              color: AppColors.primary, size: 22),
        ),
        title: Text(record.reference,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${isFull ? 'Complet' : 'Partiel'} • ${_dateFmt.format(record.createdAt)}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _Chip('${record.totalProducts} produit(s)',
                    AppColors.primary),
                const SizedBox(width: 6),
                if (record.discrepancyCount > 0)
                  _Chip('${record.discrepancyCount} écart(s)',
                      AppColors.warning)
                else
                  _Chip('Aucun écart', AppColors.accent),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.visibility_rounded,
              size: 18, color: AppColors.primary),
          tooltip: 'Voir le détail',
          onPressed: onDetail,
        ),
        onTap: onDetail,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Detail dialog ────────────────────────────────────────────────────────────

class _InventoryDetailDialog extends ConsumerWidget {
  final String inventoryId;
  const _InventoryDetailDialog({required this.inventoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(inventoryDetailProvider(inventoryId));

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Icon(Icons.inventory_2_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Détail de l\'inventaire',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            Expanded(
              child: asyncData.when(
                data: (inv) => _DetailBody(inv: inv),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Erreur: $e',
                      style: const TextStyle(color: AppColors.error)),
                ),
              ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
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

class _DetailBody extends StatelessWidget {
  final InventoryModel inv;
  const _DetailBody({required this.inv});

  @override
  Widget build(BuildContext context) {
    final discrepancies = inv.items.where((i) => i.diff.abs() > 0.001).toList();
    final exact = inv.items.where((i) => i.diff.abs() <= 0.001).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow('Référence', inv.reference),
                      _InfoRow('Type',
                          inv.inventoryType == 'full' ? 'Complet' : 'Partiel'),
                      _InfoRow('Date', _dateFmt.format(inv.createdAt)),
                      if (inv.notes != null)
                        _InfoRow('Notes', inv.notes!),
                    ]),
              ),
              Column(children: [
                _StatBadge('${inv.totalProducts}', 'Produits',
                    AppColors.primary),
                const SizedBox(height: 8),
                _StatBadge('${inv.discrepancyCount}', 'Écarts',
                    inv.discrepancyCount > 0
                        ? AppColors.warning
                        : AppColors.accent),
              ]),
            ]),
          ),
          const SizedBox(height: 16),

          // Discrepancies
          if (discrepancies.isNotEmpty) ...[
            Text('Écarts détectés (${discrepancies.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            ...discrepancies.map((item) => _ItemRow(item: item)),
            const SizedBox(height: 16),
          ],

          // Exact
          if (exact.isNotEmpty) ...[
            Text('Conformes (${exact.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            ...exact.map((item) => _ItemRow(item: item)),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label : ',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatBadge(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(label,
              style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final InventoryResultItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final diff = item.diff;
    final hasDiscrepancy = diff.abs() > 0.001;
    final diffColor = !hasDiscrepancy
        ? AppColors.textSecondary
        : diff > 0
            ? AppColors.accent
            : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: hasDiscrepancy
            ? diffColor.withValues(alpha: 0.05)
            : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasDiscrepancy
              ? diffColor.withValues(alpha: 0.3)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(item.productName,
                style: const TextStyle(fontSize: 13)),
          ),
          Text('Sys: ${_qtyFmt.format(item.expectedQty)}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          Text('Compté: ${_qtyFmt.format(item.countedQty)}',
              style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 12),
          Text(
            diff.abs() < 0.001
                ? '—'
                : (diff > 0
                    ? '+${_qtyFmt.format(diff)}'
                    : _qtyFmt.format(diff)),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: diffColor),
          ),
        ],
      ),
    );
  }
}
