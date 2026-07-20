import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_connect/core/permissions.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';
import 'package:pos_connect/providers/permission_provider.dart';
import 'package:pos_connect/providers/restaurant_provider.dart';

class TablesScreen extends ConsumerWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(tablesProvider);
    final canCreate = ref.watch(hasPermissionProvider(Perm.tablesCreate));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Plan de salle',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.restaurant_menu_rounded, color: AppColors.primary),
            tooltip: 'Vue cuisine',
            onPressed: () => context.push('/restaurant/kitchen'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: () => ref.invalidate(tablesProvider),
          ),
        ],
      ),
      body: tablesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text(extractAnyError(e), style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(tablesProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (tables) => tables.isEmpty
            ? _EmptyState(onAdd: canCreate ? () => _showAddTableDialog(context, ref) : null)
            : _TableGrid(tables: tables),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showAddTableDialog(context, ref),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter une table'),
            )
          : null,
    );
  }

  Future<void> _showAddTableDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    int capacity = 4;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 420, maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nouvelle table',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom de la table',
                      hintText: 'Table 1, Terrasse A…',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.people_outline_rounded, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      const Text('Capacité :', style: TextStyle(fontSize: 15)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () => setState(() { if (capacity > 1) capacity--; }),
                        color: AppColors.primary,
                      ),
                      SizedBox(
                        width: 36,
                        child: Text('$capacity',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        onPressed: () => setState(() => capacity++),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          Navigator.pop(ctx);
                          try {
                            await RestaurantRepository().createTable(
                              name: nameCtrl.text.trim(),
                              capacity: capacity,
                            );
                            ref.invalidate(tablesProvider);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(extractAnyError(e)),
                                backgroundColor: AppColors.error,
                              ));
                            }
                          }
                        },
                        child: const Text('Créer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TableGrid extends ConsumerWidget {
  final List<RestaurantTableModel> tables;
  const _TableGrid({required this.tables});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemCount: tables.length,
        itemBuilder: (_, i) => _TableCard(table: tables[i]),
      ),
    );
  }
}

class _TableCard extends ConsumerWidget {
  final RestaurantTableModel table;
  const _TableCard({required this.table});

  Color get _color {
    if (table.isOccupied) return AppColors.warning;
    if (table.isReserved) return AppColors.info;
    return AppColors.success;
  }

  IconData get _icon {
    if (table.isOccupied) return Icons.people_rounded;
    if (table.isReserved) return Icons.event_available_rounded;
    return Icons.chair_rounded;
  }

  String get _label {
    if (table.isOccupied) return 'Occupée';
    if (table.isReserved) return 'Réservée';
    return 'Libre';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit   = ref.watch(hasPermissionProvider(Perm.tablesUpdate));
    final canDelete = ref.watch(hasPermissionProvider(Perm.tablesDelete));
    return GestureDetector(
      onTap: () => _openOrder(context),
      onLongPress: (canEdit || canDelete)
          ? () => _showOptions(context, ref, canEdit: canEdit, canDelete: canDelete)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _color, width: 2),
          boxShadow: [
            BoxShadow(
              color: _color.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_icon, color: _color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(table.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_label,
                  style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline_rounded, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 2),
                Text('${table.capacity}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
            if (table.waiterName != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline_rounded, size: 11, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      table.waiterName!,
                      style: const TextStyle(fontSize: 10, color: AppColors.primary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openOrder(BuildContext context) async {
    if (table.isOccupied) {
      try {
        final order = await RestaurantRepository().getTableOrder(table.id);
        if (order != null && context.mounted) {
          context.push('/restaurant/commande/${order.id}');
          return;
        }
      } catch (_) {}
    }
    if (context.mounted) {
      context.push('/restaurant/commandes', extra: table.id);
    }
  }

  Future<void> _showOptions(BuildContext context, WidgetRef ref, {bool canEdit = false, bool canDelete = false}) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEdit) ...[
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: AppColors.primary),
                title: const Text('Modifier la table'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showEditDialog(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_pin_rounded, color: AppColors.info),
                title: const Text('Assigner un serveur'),
                subtitle: table.waiterName != null
                    ? Text(table.waiterName!, style: const TextStyle(color: AppColors.primary))
                    : const Text('Aucun serveur assigné'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showAssignWaiterDialog(context, ref);
                },
              ),
              if (table.isFree) ListTile(
                leading: const Icon(Icons.event_available_rounded, color: AppColors.info),
                title: const Text('Marquer comme réservée'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await RestaurantRepository().updateTable(table.id, status: 'reserved');
                    ref.invalidate(tablesProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
                      );
                    }
                  }
                },
              ),
            ],
            if (canDelete) ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              title: const Text('Supprimer', style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Supprimer la table'),
                    content: Text('Supprimer "${table.name}" ?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Supprimer', style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    await RestaurantRepository().deleteTable(table.id);
                    ref.invalidate(tablesProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
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

  Future<void> _showAssignWaiterDialog(BuildContext context, WidgetRef ref) async {
    List<RestaurantWaiterModel>? waiters;
    try {
      waiters = await RestaurantRepository().getWaiters();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
        );
      }
      return;
    }
    if (!context.mounted) return;

    String? selectedId = table.waiterId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Serveur — ${table.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ignore: deprecated_member_use
                RadioListTile<String?>(
                  value: null,
                  groupValue: selectedId,
                  title: const Text('Aucun serveur'),
                  onChanged: (v) => setState(() => selectedId = v),
                ),
                // ignore: deprecated_member_use
                ...waiters!.map((w) => RadioListTile<String?>(
                  value: w.id,
                  groupValue: selectedId,
                  title: Text(w.name.isNotEmpty ? w.name : w.username),
                  subtitle: w.name.isNotEmpty ? Text(w.username) : null,
                  onChanged: (v) => setState(() => selectedId = v),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await RestaurantRepository().assignWaiter(table.id, selectedId);
                  ref.invalidate(tablesProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController(text: table.name);
    int capacity = table.capacity;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 420, maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Modifier la table',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom de la table',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.people_outline_rounded, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      const Text('Capacité :', style: TextStyle(fontSize: 15)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () => setState(() { if (capacity > 1) capacity--; }),
                        color: AppColors.primary,
                      ),
                      SizedBox(
                        width: 36,
                        child: Text('$capacity',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        onPressed: () => setState(() => capacity++),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            await RestaurantRepository().updateTable(
                              table.id,
                              name: nameCtrl.text.trim(),
                              capacity: capacity,
                            );
                            ref.invalidate(tablesProvider);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(extractAnyError(e)), backgroundColor: AppColors.error),
                              );
                            }
                          }
                        },
                        child: const Text('Enregistrer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onAdd;
  const _EmptyState({this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.table_restaurant_rounded, size: 72, color: AppColors.divider),
          const SizedBox(height: 16),
          const Text('Aucune table configurée',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          const Text('Ajoutez vos tables pour commencer à prendre des commandes',
              style: TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ajouter une table'),
          ),
        ],
      ),
    );
  }
}
