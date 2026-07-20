import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/models/pos_register_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/repositories/warehouse_repository.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/shared/widgets/limit_exceeded_dialog.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _warehousesProvider =
    FutureProvider.autoDispose<List<WarehouseModel>>((ref) async {
  return WarehouseRepository().listWarehouses();
});

final _registersProvider = FutureProvider.autoDispose
    .family<List<PosRegisterModel>, String>((ref, warehouseId) async {
  return WarehouseRepository().listRegisters(warehouseId);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              children: [
                const Flexible(
                  child: Text(
                    'Dépôts & Caisses',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canCreate) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _showWarehouseDialog(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nouveau dépôt'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Gérez vos sites de stockage et les caisses enregistreuses associées.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
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
                        const Text('Aucun dépôt configuré',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        if (canCreate)
                          FilledButton.icon(
                            onPressed: () =>
                                _showWarehouseDialog(context, ref),
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
                      const SizedBox(height: 10),
                  itemBuilder: (_, i) => _WarehouseSection(
                    warehouse: warehouses[i],
                    canUpdate: canUpdate,
                    canDelete: canDelete,
                    onRefresh: () {
                      ref.invalidate(_warehousesProvider);
                      ref.invalidate(warehouseListProvider);
                    },
                    onRefreshRegisters: () =>
                        ref.invalidate(_registersProvider(warehouses[i].id)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showWarehouseDialog(
      BuildContext context, WidgetRef ref) async {
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
//  Section dépôt (avec caisses)
// ══════════════════════════════════════════════════════════════════════════════

class _WarehouseSection extends ConsumerWidget {
  final WarehouseModel warehouse;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onRefresh;
  final VoidCallback onRefreshRegisters;

  const _WarehouseSection({
    required this.warehouse,
    required this.canUpdate,
    required this.canDelete,
    required this.onRefresh,
    required this.onRefreshRegisters,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registersAsync = ref.watch(_registersProvider(warehouse.id));

    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: warehouse.isDefault
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.divider,
          width: warehouse.isDefault ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── En-tête dépôt ────────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
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
                const SizedBox(width: 12),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                          ),
                          if (warehouse.isDefault)
                            _Badge(
                                label: 'Par défaut',
                                color: AppColors.primary),
                          if (warehouse.isClaimed)
                            _Badge(
                                label: 'Installé',
                                color: AppColors.success),
                          if (!warehouse.isActive)
                            _Badge(
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
                      // Compteur caisses
                      registersAsync.whenOrNull(
                        data: (regs) {
                          final active =
                              regs.where((r) => r.isActive).length;
                          return Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '$active caisse${active != 1 ? 's' : ''} active${active != 1 ? 's' : ''}  •  ${regs.length} au total',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                            ),
                          );
                        },
                      ) ??
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
                // Menu dépôt
                if (canUpdate || canDelete)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: AppColors.textSecondary, size: 20),
                    itemBuilder: (_) => [
                      if (canUpdate)
                        const PopupMenuItem(
                            value: 'edit', child: Text('Modifier le dépôt')),
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
                    onSelected: (a) => _handleWarehouseAction(context, a),
                  ),
              ],
            ),
          ),

          // ── Séparateur + liste caisses ───────────────────────────────────
          const Divider(height: 1, color: AppColors.divider),
          registersAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Erreur caisses : ${extractAnyError(e)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.error)),
            ),
            data: (registers) => _RegistersList(
              warehouseId: warehouse.id,
              registers: registers,
              canUpdate: canUpdate,
              canDelete: canDelete,
              onRefresh: onRefreshRegisters,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleWarehouseAction(
      BuildContext context, String action) async {
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Liste des caisses d'un dépôt
// ══════════════════════════════════════════════════════════════════════════════

class _RegistersList extends StatelessWidget {
  final String warehouseId;
  final List<PosRegisterModel> registers;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onRefresh;

  const _RegistersList({
    required this.warehouseId,
    required this.registers,
    required this.canUpdate,
    required this.canDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (registers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.point_of_sale_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Aucune caisse — les caisses sont créées automatiquement\nlors de la première ouverture de session.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                if (canUpdate)
                  TextButton.icon(
                    onPressed: () =>
                        _showAddRegister(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Ajouter'),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6)),
                  ),
              ],
            ),
          )
        else ...[
          ...registers.map((reg) => _RegisterTile(
                warehouseId: warehouseId,
                register: reg,
                canUpdate: canUpdate,
                canDelete: canDelete,
                onRefresh: onRefresh,
              )),
          if (canUpdate)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showAddRegister(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Ajouter une caisse'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _showAddRegister(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RegisterDialog(
        warehouseId: warehouseId,
        onSaved: onRefresh,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Tuile individuelle caisse
// ══════════════════════════════════════════════════════════════════════════════

class _RegisterTile extends StatelessWidget {
  final String warehouseId;
  final PosRegisterModel register;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onRefresh;

  const _RegisterTile({
    required this.warehouseId,
    required this.register,
    required this.canUpdate,
    required this.canDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border:
            Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: register.isActive
                ? AppColors.accent.withValues(alpha: 0.12)
                : AppColors.textSecondary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.point_of_sale_rounded,
            size: 17,
            color: register.isActive
                ? AppColors.accent
                : AppColors.textSecondary,
          ),
        ),
        title: Text(
          register.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: register.isActive
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
        subtitle: Text(
          'ID appareil : ${_shortId(register.deviceId)}',
          style: const TextStyle(
              fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!register.isActive)
              _Badge(label: 'Inactif', color: AppColors.textSecondary),
            if (canUpdate || canDelete)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: AppColors.textSecondary),
                itemBuilder: (_) => [
                  if (canUpdate)
                    const PopupMenuItem(
                        value: 'edit', child: Text('Renommer')),
                  if (canUpdate)
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(register.isActive
                          ? 'Désactiver'
                          : 'Activer'),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Supprimer',
                          style: TextStyle(color: AppColors.error)),
                    ),
                ],
                onSelected: (a) => _handleAction(context, a),
              ),
          ],
        ),
      ),
    );
  }

  String _shortId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}…';
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    final repo = WarehouseRepository();
    try {
      switch (action) {
        case 'edit':
          await showDialog<void>(
            context: context,
            builder: (_) => _RegisterDialog(
              warehouseId: warehouseId,
              register: register,
              onSaved: onRefresh,
            ),
          );
        case 'toggle':
          await repo.updateRegister(warehouseId, register.id,
              isActive: !register.isActive);
          onRefresh();
        case 'delete':
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Supprimer la caisse'),
              content: Text(
                  'Supprimer « ${register.name} » ? L\'historique des sessions reste conservé.'),
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
            await repo.deleteRegister(warehouseId, register.id);
            onRefresh();
          }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Dialogs
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
  late final TextEditingController _desc;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.warehouse?.name ?? '');
    _desc =
        TextEditingController(text: widget.warehouse?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save({bool force = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = WarehouseRepository();
      final desc = _desc.text.trim().isEmpty ? null : _desc.text.trim();
      if (widget.warehouse == null) {
        await repo.createWarehouse(_name.text.trim(),
            description: desc, force: force);
      } else {
        await repo.updateWarehouse(widget.warehouse!.id,
            name: _name.text.trim(), description: desc ?? '');
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      // 402 = limit exceeded → show pricing warning with mandatory checkbox
      final confirmed = await handleLimitExceeded(context, e);
      if (!mounted) return;
      if (confirmed) { _save(force: true); return; }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e'),
        backgroundColor: AppColors.error,
      ));
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
                    hintText: 'Ex : Magasin principal, Entrepôt Nord…'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Le nom est obligatoire'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(
                    labelText: 'Description (optionnel)',
                    hintText: 'Adresse, notes…'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(isEdit ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RegisterDialog extends StatefulWidget {
  final String warehouseId;
  final PosRegisterModel? register;
  final VoidCallback onSaved;
  const _RegisterDialog(
      {required this.warehouseId, this.register, required this.onSaved});
  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.register?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save({bool force = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = WarehouseRepository();
      if (widget.register == null) {
        await repo.createRegister(widget.warehouseId, _name.text.trim(),
            force: force);
      } else {
        await repo.updateRegister(widget.warehouseId, widget.register!.id,
            name: _name.text.trim());
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      // 402 = limit exceeded → show pricing warning with mandatory checkbox
      final confirmed = await handleLimitExceeded(context, e);
      if (!mounted) return;
      if (confirmed) { _save(force: true); return; }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.register != null;
    return AlertDialog(
      title: Text(isEdit ? 'Renommer la caisse' : 'Ajouter une caisse'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isEdit)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Les caisses sont habituellement créées automatiquement '
                    'à la première ouverture de session. Vous pouvez aussi en '
                    'créer une manuellement pour la pré-configurer.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Nom de la caisse *',
                    hintText: 'Ex : Caisse 1, Caisse Nord…'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Le nom est obligatoire'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(isEdit ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Badge helper
// ══════════════════════════════════════════════════════════════════════════════

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
