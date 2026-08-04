import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/stock_movement_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/providers/entrepot_provider.dart';
import 'package:pos_connect/providers/permission_provider.dart';
import 'package:pos_connect/providers/product_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';
import 'package:pos_connect/services/offline_cache_service.dart';

final _fmt = NumberFormat('#,##0.##', 'fr');
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

// Après un ajustement/une distribution à l'entrepôt, la page Produits (et le
// cache local Android, qui ne se resynchronise pas tout seul avant le prochain
// cycle périodique) doivent refléter le nouveau stock par dépôt immédiatement —
// sans ça, l'écran Produits continue d'afficher l'ancien stock (voire un total
// global au lieu du stock réel du dépôt actif) jusqu'à la prochaine synchro.
Future<void> _refreshProductsAfterEntrepotChange(WidgetRef ref) async {
  final warehouseId = ref.read(activeWarehouseProvider)?.id;
  await OfflineCacheService.instance.syncAll(warehouseId: warehouseId);
  ref.invalidate(productsProvider);
}

class EntrepotScreen extends ConsumerWidget {
  const EntrepotScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entrepotAsync = ref.watch(entrepotProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Entrepôt',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Stock central — réceptionnez la marchandise puis distribuez-la vers vos dépôts.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: entrepotAsync.when(
                data: (entrepot) => entrepot == null
                    ? const _SetupView()
                    : _EntrepotContent(entrepot: entrepot),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupView extends ConsumerStatefulWidget {
  const _SetupView();
  @override
  ConsumerState<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<_SetupView> {
  bool _loading = false;

  Future<void> _create() async {
    setState(() => _loading = true);
    try {
      await ref.read(entrepotRepositoryProvider).createEntrepot();
      ref.invalidate(entrepotProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur lors de la création de l\'entrepôt'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(hasPermissionProvider(Perm.entrepotCreate));
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warehouse, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          const Text('Aucun entrepôt configuré',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'Créez votre entrepôt central pour commencer à recevoir et distribuer du stock.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (canCreate)
            ElevatedButton.icon(
              onPressed: _loading ? null : _create,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add),
              label: const Text('Créer l\'entrepôt'),
            ),
        ],
      ),
    );
  }
}

class _EntrepotContent extends ConsumerStatefulWidget {
  final WarehouseModel entrepot;
  const _EntrepotContent({required this.entrepot});

  @override
  ConsumerState<_EntrepotContent> createState() => _EntrepotContentState();
}

class _EntrepotContentState extends ConsumerState<_EntrepotContent> {
  late final int _initialTab;

  @override
  void initState() {
    super.initState();
    // Capturé une seule fois (DefaultTabController.initialIndex n'est lu
    // qu'à la création) puis remis à 0 pour ne pas rester coincé sur
    // l'onglet Historique lors d'un prochain accès normal à l'écran.
    _initialTab = ref.read(entrepotInitialTabProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(entrepotInitialTabProvider.notifier).state = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entrepot = widget.entrepot;
    return DefaultTabController(
      length: 2,
      initialIndex: _initialTab,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabBar(
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'Produits'),
              Tab(text: 'Historique'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                _ProductsTab(entrepot: entrepot),
                _HistoryTab(entrepot: entrepot),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Produits ─────────────────────────────────────────────────────────────

class _ProductsTab extends ConsumerWidget {
  final WarehouseModel entrepot;
  const _ProductsTab({required this.entrepot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(entrepotProductsProvider);
    final canManage = ref.watch(hasPermissionProvider(Perm.entrepotCreate));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Rechercher un produit...',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) =>
              ref.read(entrepotProductSearchProvider.notifier).state = v,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: productsAsync.when(
            data: (result) {
              if (result.data.isEmpty) {
                return const Center(
                    child: Text('Aucun produit', style: TextStyle(color: AppColors.textSecondary)));
              }
              return ListView.separated(
                itemCount: result.data.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final p = result.data[i];
                  return _ProductRow(product: p, entrepot: entrepot, canManage: canManage);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur: $e')),
          ),
        ),
      ],
    );
  }
}

class _ProductRow extends ConsumerWidget {
  final ProductModel product;
  final WarehouseModel entrepot;
  final bool canManage;
  const _ProductRow({required this.product, required this.entrepot, required this.canManage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = product.stock ?? 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('Stock entrepôt: ${_fmt.format(stock)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: stock <= 0 ? AppColors.error : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      )),
                ],
              ),
            ),
            if (canManage) ...[
              IconButton(
                tooltip: 'Ajuster le stock',
                icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.textSecondary),
                onPressed: () => _showAdjustDialog(context, ref, product),
              ),
              FilledButton.icon(
                onPressed: stock > 0
                    ? () => _showDistributeDialog(context, ref, product, stock)
                    : null,
                icon: const Icon(Icons.call_split_rounded, size: 16),
                label: const Text('Distribuer'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAdjustDialog(BuildContext context, WidgetRef ref, ProductModel product) {
    final ctrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(product.name, style: const TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Quantité (ex: 10 ou -5)',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Motif (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final qty = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (qty == null || qty == 0) return;
              try {
                await ref.read(entrepotRepositoryProvider).adjustStock(
                      product.id, qty, reason: reasonCtrl.text.trim(),
                    );
                ref.invalidate(entrepotProductsProvider);
                ref.invalidate(entrepotMovementsProvider);
                await _refreshProductsAfterEntrepotChange(ref);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Erreur lors de l\'ajustement'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
  }

  void _showDistributeDialog(
      BuildContext context, WidgetRef ref, ProductModel product, int available) {
    showDialog(
      context: context,
      builder: (_) => _DistributeDialog(product: product, available: available),
    );
  }
}

class _DistributeDialog extends ConsumerStatefulWidget {
  final ProductModel product;
  final int available;
  const _DistributeDialog({required this.product, required this.available});

  @override
  ConsumerState<_DistributeDialog> createState() => _DistributeDialogState();
}

class _DistributeDialogState extends ConsumerState<_DistributeDialog> {
  final Map<String, TextEditingController> _ctrls = {};
  bool _loading = false;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(List<WarehouseModel> depots) async {
    final allocations = <Map<String, dynamic>>[];
    double total = 0;
    for (final d in depots) {
      final qty = double.tryParse(_ctrls[d.id]?.text.replaceAll(',', '.') ?? '');
      if (qty != null && qty > 0) {
        allocations.add({'warehouse_id': d.id, 'quantity': qty});
        total += qty;
      }
    }
    if (allocations.isEmpty) return;
    if (total > widget.available) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Stock insuffisant à l\'entrepôt (disponible: ${widget.available})'),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(entrepotRepositoryProvider).distribute(widget.product.id, allocations);
      ref.invalidate(entrepotProductsProvider);
      ref.invalidate(entrepotMovementsProvider);
      await _refreshProductsAfterEntrepotChange(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final depots = (ref.watch(warehouseListProvider).valueOrNull ?? [])
        .where((w) => !w.isEntrepot)
        .toList();

    return AlertDialog(
      title: Text('Distribuer — ${widget.product.name}',
          style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Disponible à l\'entrepôt: ${widget.available}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            if (depots.isEmpty)
              const Text('Aucun dépôt disponible.', style: TextStyle(color: AppColors.textSecondary))
            else
              ...depots.map((d) {
                _ctrls.putIfAbsent(d.id, () => TextEditingController());
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(d.name, style: const TextStyle(fontSize: 13))),
                      SizedBox(
                        width: 100,
                        child: TextFormField(
                          controller: _ctrls[d.id],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            hintText: '0',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _loading || depots.isEmpty ? null : () => _submit(depots),
          child: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Valider'),
        ),
      ],
    );
  }
}

// ── Historique ───────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  final WarehouseModel entrepot;
  const _HistoryTab({required this.entrepot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(entrepotMovementsProvider);
    final productFilter = ref.watch(entrepotMovementProductFilterProvider);

    return Column(
      children: [
        if (productFilter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                label: Text('Produit : ${productFilter.name}',
                    style: const TextStyle(fontSize: 12)),
                onDeleted: () => ref
                    .read(entrepotMovementProductFilterProvider.notifier)
                    .state = null,
              ),
            ),
          ),
        Expanded(
          child: movementsAsync.when(
            data: (result) {
              if (result.data.isEmpty) {
                return const Center(
                    child: Text('Aucun mouvement',
                        style: TextStyle(color: AppColors.textSecondary)));
              }
              return ListView.separated(
                itemCount: result.data.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _MovementRow(mv: result.data[i]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur: $e')),
          ),
        ),
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  final StockMovementModel mv;
  const _MovementRow({required this.mv});

  @override
  Widget build(BuildContext context) {
    final isIn = mv.type.toUpperCase() == 'IN';
    return ListTile(
      dense: true,
      leading: Icon(
        isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
        color: isIn ? AppColors.success : AppColors.error,
      ),
      title: Text(mv.productName ?? 'Produit', style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '${mv.sourceLabel}${mv.note != null && mv.note!.isNotEmpty ? ' — ${mv.note}' : ''}'
        '${mv.userFullName != null && mv.userFullName!.isNotEmpty ? ' — par ${mv.userFullName}' : ''}',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${isIn ? '+' : ''}${_fmt.format(mv.quantity)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isIn ? AppColors.success : AppColors.error,
            ),
          ),
          Text(_dateFmt.format(mv.createdAt),
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
