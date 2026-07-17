import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/repositories/warehouse_repository.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _warehousesProvider =
    FutureProvider.autoDispose<List<WarehouseModel>>((ref) async {
  return WarehouseRepository().listWarehouses();
});

// ══════════════════════════════════════════════════════════════════════════════
//  Écran principal
// ══════════════════════════════════════════════════════════════════════════════

class WarehousesScreen extends ConsumerWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(_warehousesProvider);
    final user = ref.watch(authProvider).user;
    final canCreate = user?.hasPermission(Perm.warehousesCreate) ?? false;
    final canUpdate = user?.hasPermission(Perm.warehousesUpdate) ?? false;
    final canDelete = user?.hasPermission(Perm.warehousesDelete) ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              children: [
                const Text(
                  'Dépôts',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const Spacer(),
                if (canCreate)
                  FilledButton.icon(
                    onPressed: () => _showCreateDialog(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nouveau dépôt'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Gérez vos sites de stockage (magasins, entrepôts, points de vente).',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 20),

          // ── Liste ─────────────────────────────────────────────────────────
          Expanded(
            child: warehousesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text('Erreur : $e',
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(_warehousesProvider),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (warehouses) {
                if (warehouses.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warehouse_outlined,
                            size: 64,
                            color: AppColors.textSecondary
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        const Text(
                          'Aucun dépôt configuré',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        if (canCreate)
                          FilledButton.icon(
                            onPressed: () =>
                                _showCreateDialog(context, ref),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Créer le premier dépôt'),
                          ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: warehouses.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) => _WarehouseCard(
                    warehouse: warehouses[i],
                    canUpdate: canUpdate,
                    canDelete: canDelete,
                    onRefresh: () {
                      ref.invalidate(_warehousesProvider);
                      ref.invalidate(warehouseListProvider);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _WarehouseDialog(
        onSaved: () {
          ref.invalidate(_warehousesProvider);
          ref.invalidate(warehouseListProvider);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Carte dépôt
// ══════════════════════════════════════════════════════════════════════════════

class _WarehouseCard extends StatelessWidget {
  final WarehouseModel warehouse;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onRefresh;

  const _WarehouseCard({
    required this.warehouse,
    required this.canUpdate,
    required this.canDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: warehouse.isDefault
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icône
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: warehouse.isActive
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.textSecondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                warehouse.isClaimed
                    ? Icons.store_rounded
                    : Icons.warehouse_outlined,
                color: warehouse.isActive
                    ? AppColors.primary
                    : AppColors.textSecondary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),

            // Infos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        warehouse.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      if (warehouse.isDefault)
                        _Chip(
                            label: 'Par défaut',
                            color: AppColors.primary),
                      if (warehouse.isClaimed)
                        _Chip(
                            label: 'Installé',
                            color: AppColors.success),
                      if (!warehouse.isActive)
                        _Chip(
                            label: 'Inactif',
                            color: AppColors.textSecondary),
                    ],
                  ),
                  if (warehouse.description != null &&
                      warehouse.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      warehouse.description!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Actions
            if (canUpdate || canDelete)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    color: AppColors.textSecondary),
                itemBuilder: (_) => [
                  if (canUpdate)
                    const PopupMenuItem(
                        value: 'edit', child: Text('Modifier')),
                  if (canUpdate && !warehouse.isDefault)
                    const PopupMenuItem(
                        value: 'default',
                        child: Text('Définir par défaut')),
                  if (canUpdate)
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(warehouse.isActive
                          ? 'Désactiver'
                          : 'Activer'),
                    ),
                  if (canDelete && !warehouse.isDefault)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Supprimer',
                          style: TextStyle(color: AppColors.error)),
                    ),
                ],
                onSelected: (action) => _handleAction(context, action),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    final repo = WarehouseRepository();
    try {
      switch (action) {
        case 'edit':
          await showDialog<void>(
            context: context,
            builder: (_) => _WarehouseDialog(
              warehouse: warehouse,
              onSaved: onRefresh,
            ),
          );
        case 'default':
          await repo.setDefault(warehouse.id);
          onRefresh();
        case 'toggle':
          await repo.updateWarehouse(warehouse.id,
              isActive: !warehouse.isActive);
          onRefresh();
        case 'delete':
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Supprimer le dépôt'),
              content: Text(
                  'Supprimer « ${warehouse.name} » ? Cette action est irréversible.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annuler')),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await repo.deleteWarehouse(warehouse.id);
            onRefresh();
          }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Dialog création / modification
// ══════════════════════════════════════════════════════════════════════════════

class _WarehouseDialog extends StatefulWidget {
  final WarehouseModel? warehouse;
  final VoidCallback onSaved;

  const _WarehouseDialog({this.warehouse, required this.onSaved});

  @override
  State<_WarehouseDialog> createState() => _WarehouseDialogState();
}

class _WarehouseDialogState extends State<_WarehouseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.warehouse?.name ?? '');
    _description =
        TextEditingController(text: widget.warehouse?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = WarehouseRepository();
      if (widget.warehouse == null) {
        await repo.createWarehouse(
          _name.text.trim(),
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        );
      } else {
        await repo.updateWarehouse(
          widget.warehouse!.id,
          name: _name.text.trim(),
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.warehouse != null;
    return AlertDialog(
      title: Text(isEdit ? 'Modifier le dépôt' : 'Nouveau dépôt'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nom du dépôt *',
                  hintText: 'Ex : Magasin principal, Entrepôt Nord…',
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Le nom est obligatoire'
                        : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Description (optionnel)',
                  hintText: 'Adresse, notes…',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(isEdit ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Widget helper
// ══════════════════════════════════════════════════════════════════════════════

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
